"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";

/**
 * Notifications are created by database triggers; the only thing a recipient
 * can do is mark them read or clear them. RLS scopes every statement here to
 * the caller's own rows.
 */

export async function markNotificationRead(
  id: string,
): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id)
    .is("read_at", null);

  if (error) return fail(describeDatabaseError(error));
  revalidatePath("/", "layout");
  return ok(undefined);
}

export async function markAllNotificationsRead(): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("user_id", user.id)
    .is("read_at", null);

  if (error) return fail(describeDatabaseError(error));
  revalidatePath("/", "layout");
  return ok(undefined);
}
