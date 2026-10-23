"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { TeamMessage } from "@/lib/supabase/database.types";

/**
 * The team room.
 *
 * Both of these run as the signed-in user, so row-level security decides what
 * is allowed: the insert policy requires `author_id = auth.uid()`, which is
 * what stops a message being posted under somebody else's name, and the delete
 * policy allows an author or an admin. Neither rule is re-implemented here —
 * this is the form, not the authority.
 */

/** Matches the database's own check, so the UI can refuse before a round trip. */
const MAX_LENGTH = 4000;

/**
 * Post a message, and hand the saved row back.
 *
 * The row is returned rather than nothing so the sender sees what they wrote
 * straight away. Everyone else finds out over realtime, but waiting for your
 * own words to come back from the server is the one case where that round
 * trip is felt: the box empties, and for a moment it looks like the message
 * went nowhere. The room drops the duplicate when the broadcast arrives.
 */
export async function sendTeamMessage(
  body: string,
): Promise<ActionResult<TeamMessage>> {
  const text = body.trim();
  if (!text) return fail("chat.emptyMessage");
  if (text.length > MAX_LENGTH) return fail("chat.tooLong");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.signedOut");

  const { data, error } = await supabase
    .from("team_messages")
    .insert({ author_id: user.id, body: text })
    .select("*")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/chat");
  return ok(data as TeamMessage);
}

export async function deleteTeamMessage(id: string): Promise<ActionResult<void>> {
  const supabase = await createClient();

  // No role check here on purpose. The policy allows the author or an admin,
  // and a second rule written in TypeScript would be one more thing to keep
  // in step with it.
  const { error, count } = await supabase
    .from("team_messages")
    .delete({ count: "exact" })
    .eq("id", id);

  if (error) return fail(describeDatabaseError(error));
  // RLS filters rather than refuses: a delete somebody is not allowed to make
  // removes nothing and reports no error.
  if (!count) return fail("chat.notYours");

  revalidatePath("/chat");
  return ok(undefined);
}
