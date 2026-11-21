"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import { signedInWithSecondStep } from "@/lib/auth/second-step";
import {
  describeDatabaseError,
  fail,
  fieldErrorsFrom,
  ok,
  type ActionResult,
} from "@/lib/action-result";
import { emailSchema, userRoleSchema } from "@/lib/validation";

/**
 * Adding somebody to Maham Tasks — the only way in.
 *
 * Maham Tasks runs on Maham One's database, and its accounts are Maham One's:
 * everyone signs in to both with the same email and password. An admin
 * invites somebody by email (tasks.add_teammate); they are in Maham Tasks once
 * they sign in here with a confirmed Maham One account that has that email
 * (tasks.join, when their profile is looked up), within 30 days. The answer is
 * the same whether or not a Maham One account has the email, and nobody is
 * put in without signing in themselves.
 *
 * Nothing here holds Maham One's service key, and no admin sets or learns
 * anybody's password: the account opens Maham One too, payroll and all for
 * some, so it is theirs to look after (the sign-in page’s “Forgot your
 * password?”).
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

/** What adding somebody did: invited, or already in Maham Tasks. */
export type AddedTeammate = { status: "invited" | "already"; email: string };

async function requireAdmin(): Promise<
  | { supabase: Awaited<ReturnType<typeof createClient>>; userId: string }
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

  // Managing the team waits for two-step sign-in, here and in the database
  // (tasks.add_teammate and tasks.remove_two_step check it too).
  if (!(await signedInWithSecondStep(supabase))) {
    return { error: "action.needsTwoStep" };
  }

  return { supabase, userId: user.id };
}

export async function addTeamMember(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<AddedTeammate>> {
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
  const { supabase } = permitted;
  const { email, fullName, role } = parsed.data;

  const { data, error } = await supabase.rpc("add_teammate", {
    p_email: email,
    p_full_name: fullName,
    p_role: role,
  });
  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/team");
  const status = (data as { status?: string } | null)?.status;
  return ok({ status: status === "already" ? "already" : "invited", email });
}

/** An admin takes back an invite nobody has accepted yet. */
export async function withdrawInvite(email: string): Promise<ActionResult<void>> {
  if (!emailSchema.safeParse(email).success) return fail("action.checkFields");

  const permitted = await requireAdmin();
  if ("error" in permitted) return fail(permitted.error);

  const { error } = await permitted.supabase.from("invites").delete().eq("email", email);
  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/team");
  return ok(undefined);
}

export async function removeMemberTwoStep(
  userId: string,
): Promise<ActionResult<{ removed: number }>> {
  if (!z.string().uuid().safeParse(userId).success) {
    return fail("action.unknownMember");
  }

  const permitted = await requireAdmin();
  if ("error" in permitted) return fail(permitted.error);
  const { supabase, userId: callerId } = permitted;

  if (userId === callerId) return fail("action.ownTwoStepFromProfile");

  const { data, error } = await supabase.rpc("remove_two_step", { p_user: userId });
  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/team");
  return ok({ removed: typeof data === "number" ? data : 0 });
}
