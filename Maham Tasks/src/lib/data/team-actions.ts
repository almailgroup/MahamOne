"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { signedInWithSecondStep } from "@/lib/auth/second-step";
import { describeAuthError } from "@/lib/auth/errors";
import {
  describeDatabaseError,
  fail,
  fieldErrorsFrom,
  ok,
  type ActionResult,
} from "@/lib/action-result";
import { getI18n } from "@/lib/i18n/server";
import { emailSchema, userRoleSchema } from "@/lib/validation";

/**
 * Adding somebody to the workspace — the only way in.
 *
 * This is a company portal: people are added by whoever is responsible for
 * access, rather than admitting themselves. There is no sign-up page, and the
 * database refuses any account an admin did not add (close_self_registration),
 * which is why the account created here records who added it.
 *
 * It sends nothing. An admin creates the account with a one-time password,
 * already confirmed, and passes it on however they normally would — which also
 * keeps clear of the handful of emails an hour that a Supabase project's own
 * mail service allows.
 */

const newMemberSchema = z.object({
  fullName: z
    .string()
    .trim()
    .min(2, "validation.enterTheirName")
    .max(120, "validation.nameMax"),
  email: emailSchema,
  role: userRoleSchema,
});

/**
 * A password that survives being read down a phone line.
 *
 * No 0/O or 1/l/I, and long enough that the ambiguity is not worth the risk —
 * sixteen characters from this alphabet is about 92 bits. It is meant to be
 * replaced: the person changes it from their profile once they are in.
 */
function temporaryPassword(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const symbols = "!@#$%&*";

  const draw = (source: string, count: number) => {
    const values = new Uint32Array(count);
    crypto.getRandomValues(values);
    return [...values].map((value) => source[value % source.length]).join("");
  };

  return `${draw(alphabet, 16)}${draw(symbols, 1)}`;
}

/**
 * The two things every action here needs: proof the caller is an admin, and a
 * service-role client.
 *
 * The service-role client ignores Row Level Security completely, so this is
 * one of the few places in the codebase that has to check a role in code —
 * there is no policy left to do it. The check runs first, and against the
 * caller's own session.
 */
async function requireAdmin(): Promise<
  | { supabase: Awaited<ReturnType<typeof createClient>>; admin: ReturnType<typeof createAdminClient>; userId: string }
  | { error: string }
> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "action.sessionExpired" };

  const { data: caller } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (caller?.role !== "admin") {
    return { error: "action.adminOnly" };
  }

  // The service key can do anything to any account, so whoever is asking it
  // to must have proved who they are twice over.
  if (!(await signedInWithSecondStep(supabase))) {
    return { error: "action.needsTwoStep" };
  }

  try {
    return { supabase, admin: createAdminClient(), userId: user.id };
  } catch {
    return {
      error:
        "action.needsServiceRole",
    };
  }
}

export async function addTeamMember(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ email: string; password: string }>> {
  const parsed = newMemberSchema.safeParse({
    fullName: formData.get("fullName"),
    email: formData.get("email"),
    role: formData.get("role") ?? "member",
  });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const permitted = await requireAdmin();
  if ("error" in permitted) return fail(permitted.error);
  const { supabase, admin, userId } = permitted;

  const password = temporaryPassword();

  const { data: created, error } = await admin.auth.admin.createUser({
    email: parsed.data.email,
    password,
    // Confirmed on creation: nothing is emailed, so nothing can be missed and
    // no send quota is spent.
    email_confirm: true,
    // Which admin added them. The database lets an account in only when this
    // names an admin (close_self_registration), and app_metadata is the half
    // of an account only the service key can write — somebody signing
    // themselves up cannot set it.
    app_metadata: { added_by: userId },
    user_metadata: {
      full_name: parsed.data.fullName,
      // The app asks them to choose their own on first sign-in, and clears
      // this when they do. A nudge, not a lock: the account is already theirs,
      // and they could clear the flag themselves if they went looking.
      must_change_password: true,
    },
  });

  if (error) return fail(describeAuthError(error));
  if (!created.user) return fail("action.accountNotCreated");

  // The profile row already exists — handle_new_user creates it as the auth
  // user is inserted — so the role is set on it rather than passed in. This
  // deliberately runs as the admin who asked for it, not as the service key:
  // the trigger that guards role changes checks who is asking.
  if (parsed.data.role !== "member") {
    const { error: roleError } = await supabase
      .from("profiles")
      .update({ role: parsed.data.role })
      .eq("id", created.user.id);

    if (roleError) {
      revalidatePath("/team");
      const { t, tm } = await getI18n();
      return fail(
        t("action.roleNotSet", {
          name: parsed.data.fullName,
          reason: tm(describeDatabaseError(roleError)),
        }),
      );
    }
  }

  revalidatePath("/team");
  revalidatePath("/", "layout");

  return ok({ email: parsed.data.email, password });
}

/**
 * Issue somebody a new password.
 *
 * For the person who has locked themselves out, or was never able to sign in
 * with what they were given. The alternative is the emailed reset link, which
 * depends on the mail quota that made all of this necessary in the first
 * place, and on them still having access to the inbox.
 *
 * The new password is temporary by construction: the account is flagged, so
 * the next sign-in lands on "Choose your password" the same way a new account
 * does. An admin never learns the password anybody is actually using.
 */
export async function resetMemberPassword(
  userId: string,
): Promise<ActionResult<{ email: string; password: string }>> {
  if (!z.string().uuid().safeParse(userId).success) {
    return fail("action.unknownMember");
  }

  const permitted = await requireAdmin();
  if ("error" in permitted) return fail(permitted.error);
  const { admin, userId: callerId } = permitted;

  // Changing your own password is a different act with a different rule: it
  // asks for the current one, and that lives on the profile page.
  if (userId === callerId) {
    return fail("action.ownPasswordFromProfile");
  }

  const { data: target, error: lookupError } =
    await admin.auth.admin.getUserById(userId);

  if (lookupError || !target.user?.email) {
    return fail("action.accountNotFound");
  }

  const password = temporaryPassword();

  const { error } = await admin.auth.admin.updateUserById(userId, {
    password,
    // Spread rather than replace: the metadata carries their name, and
    // overwriting the object would lose it.
    user_metadata: { ...target.user.user_metadata, must_change_password: true },
  });

  if (error) return fail(describeAuthError(error));

  revalidatePath("/team");
  return ok({ email: target.user.email, password });
}
/**
 * Remove a teammate's authenticator app, for somebody who has lost their
 * phone.
 *
 * Without this the only way back in was the Supabase dashboard. Afterwards
 * their password alone signs them in, until they set up a new app from their
 * profile. Their own app is turned off from Profile, where it asks for a code.
 */
export async function removeMemberTwoStep(
  userId: string,
): Promise<ActionResult<{ removed: number }>> {
  if (!z.string().uuid().safeParse(userId).success) {
    return fail("action.unknownMember");
  }

  const permitted = await requireAdmin();
  if ("error" in permitted) return fail(permitted.error);
  const { admin, userId: callerId } = permitted;

  if (userId === callerId) return fail("action.ownTwoStepFromProfile");

  const { data, error } = await admin.auth.admin.mfa.listFactors({ userId });
  if (error || !data) return fail(error ? describeAuthError(error) : "action.accountNotFound");

  for (const factor of data.factors) {
    const { error: deleteError } = await admin.auth.admin.mfa.deleteFactor({
      id: factor.id,
      userId,
    });
    if (deleteError) return fail(describeAuthError(deleteError));
  }

  revalidatePath("/team");
  return ok({ removed: data.factors.length });
}
