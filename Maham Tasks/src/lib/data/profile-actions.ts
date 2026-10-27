"use server";

import { randomInt } from "node:crypto";

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
import { positionSchema, profileSchema, userRoleSchema } from "@/lib/validation";
import type { UserRole } from "@/lib/supabase/database.types";

export async function updateProfile(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<void>> {
  const parsed = profileSchema.safeParse({
    fullName: formData.get("fullName"),
    avatarUrl: formData.get("avatarUrl") ?? undefined,
  });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("profiles")
    .update({
      full_name: parsed.data.fullName,
      avatar_url: parsed.data.avatarUrl || null,
    })
    .eq("id", user.id);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/", "layout");
  return ok(undefined);
}

/**
 * Change another member's role.
 *
 * Only admins can do this, and that is enforced in the database by the
 * guard_profile_role_change trigger — not here.
 */
export async function updateMemberRole(
  userId: string,
  role: UserRole,
): Promise<ActionResult<void>> {
  // A Server Action is a public endpoint, so the arguments are validated at
  // runtime rather than trusted from the TypeScript signature.
  const parsed = userRoleSchema.safeParse(role);
  if (!parsed.success) return fail("action.unknownRole");
  if (!z.string().uuid().safeParse(userId).success) {
    return fail("action.unknownMember");
  }

  const supabase = await createClient();

  // Making somebody an admin hands them everything; the admin doing it must
  // have signed in with their authenticator app as well as the password.
  if (!(await signedInWithSecondStep(supabase))) return fail("action.needsTwoStep");

  const { data, error } = await supabase
    .from("profiles")
    .update({ role: parsed.data })
    .eq("id", userId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noPermissionRoles");

  revalidatePath("/team");
  return ok(undefined);
}

/**
 * Set a member's job position.
 *
 * Admin-only, enforced by the guard_profile_role_change trigger rather than
 * here — the same trigger that blocks self-promotion now pins job_title too.
 * Passing an empty value clears it.
 */
export async function updateMemberPosition(
  userId: string,
  jobTitle: string,
): Promise<ActionResult<void>> {
  const parsed = positionSchema.safeParse(jobTitle);
  if (!parsed.success) {
    return fail(parsed.error.issues[0]?.message ?? "action.positionInvalid");
  }
  if (!z.string().uuid().safeParse(userId).success) {
    return fail("action.unknownMember");
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("profiles")
    .update({ job_title: parsed.data || null })
    .eq("id", userId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noPermissionPositions");

  revalidatePath("/", "layout");
  return ok(undefined);
}

/** Record a newly uploaded avatar against the signed-in user's profile. */
export async function setOwnAvatar(
  publicUrl: string,
): Promise<ActionResult<void>> {
  const url = publicUrl.trim();
  if (url && !/^https?:\/\//i.test(url)) {
    return fail("action.imageNotSaved");
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("profiles")
    .update({ avatar_url: url || null })
    .eq("id", user.id);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/", "layout");
  return ok(undefined);
}

/**
 * Reminder preferences.
 *
 * RLS restricts every statement here to the caller's own row, and database
 * constraints refuse a channel switched on with nowhere to send to, so this
 * only has to translate the failure into something readable.
 */
export async function updateNotificationPreferences(input: {
  emailEnabled: boolean;
  telegramEnabled: boolean;
  whatsappEnabled: boolean;
  whatsappNumber: string;
  remindAssigned: boolean;
  remindDueSoon: boolean;
  remindOverdue: boolean;
  remindFollowUp: boolean;
  /** Left out when the column does not exist yet (before migration 37). */
  morningSummary?: boolean;
  dueSoonLeadHours: number;
}): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const number = input.whatsappNumber.trim();
  if (input.whatsappEnabled && !/^\+[1-9]\d{6,14}$/.test(number)) {
    return fail(
      "action.whatsappFormat",
    );
  }

  const lead = Math.min(168, Math.max(1, Math.round(input.dueSoonLeadHours)));

  const { error } = await supabase
    .from("notification_preferences")
    .update({
      email_enabled: input.emailEnabled,
      telegram_enabled: input.telegramEnabled,
      whatsapp_enabled: input.whatsappEnabled,
      whatsapp_number: number || null,
      remind_assigned: input.remindAssigned,
      remind_due_soon: input.remindDueSoon,
      remind_overdue: input.remindOverdue,
      remind_follow_up: input.remindFollowUp,
      ...(input.morningSummary === undefined ? {} : { morning_summary: input.morningSummary }),
      due_soon_lead_hours: lead,
    })
    .eq("user_id", user.id);

  if (error) {
    if (error.code === "23514") {
      return fail(
        "action.channelNeedsTarget",
      );
    }
    return fail(describeDatabaseError(error));
  }

  revalidatePath("/profile");
  return ok(undefined);
}

/**
 * Issue a single-use code for linking Telegram.
 *
 * The chat id can only come from Telegram itself, so the user sends this code
 * to the bot and the webhook records which chat replied.
 */
export async function createTelegramLinkCode(): Promise<
  ActionResult<{ code: string }>
> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  // Unambiguous alphabet: no O/0 or I/1 to mistype when copying by hand.
  //
  // randomInt, not Math.random: this code is the only thing standing between a
  // stranger and someone else's reminders. Math.random is a seeded PRNG whose
  // state can be recovered from a handful of outputs, and anyone can mint
  // themselves outputs by asking for codes on their own account.
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const code = Array.from(
    { length: 8 },
    () => alphabet[randomInt(alphabet.length)],
  ).join("");

  const { error } = await supabase
    .from("notification_preferences")
    .update({ telegram_link_code: code })
    .eq("user_id", user.id);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/profile");
  return ok({ code });
}

/** Disconnect Telegram and stop sending there. */
export async function unlinkTelegram(): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("notification_preferences")
    .update({
      telegram_enabled: false,
      telegram_chat_id: null,
      telegram_link_code: null,
    })
    .eq("user_id", user.id);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/profile");
  return ok(undefined);
}
