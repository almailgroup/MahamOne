"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { DirectMessage } from "@/lib/supabase/database.types";

/** A teammate, as the command palette needs them. */
export type PersonHit = {
  id: string;
  full_name: string | null;
  email: string;
  job_title: string | null;
};

/**
 * Private messages.
 *
 * Every rule lives in the migration: you read a conversation only if you are
 * in it, you post only as yourself and only where you are, and you delete
 * only what you wrote. There is no admin clause anywhere in it and there is
 * none here — this is the form, not the authority.
 */

/** Matches the column's own check, so the UI can refuse before a round trip. */
const MAX_LENGTH = 4000;

/**
 * Open the conversation with somebody, or find the one already there.
 *
 * The database decides, not this: `start_direct_conversation` is the only way
 * a conversation is created, it puts exactly two people in it, and two people
 * starting one with each other at the same moment get a single thread.
 */
export async function startConversation(
  otherId: string,
): Promise<ActionResult<string>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.signedOut");
  if (otherId === user.id) return fail("dm.notYourself");

  const { data, error } = await supabase.rpc("start_direct_conversation", {
    other: otherId,
  });

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("dm.couldNotOpen");

  revalidatePath("/messages");
  return ok(data as string);
}

/**
 * Post to a thread, and hand the saved row back.
 *
 * Returned rather than nothing for the same reason as the team room: waiting
 * for your own words to come back over realtime is the one round trip that is
 * felt. The thread drops the duplicate when the broadcast arrives.
 */
export async function sendDirectMessage(
  conversationId: string,
  body: string,
): Promise<ActionResult<DirectMessage>> {
  const text = body.trim();
  if (!text) return fail("chat.emptyMessage");
  if (text.length > MAX_LENGTH) return fail("chat.tooLong");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.signedOut");

  const { data, error } = await supabase
    .from("direct_messages")
    .insert({
      conversation_id: conversationId,
      author_id: user.id,
      body: text,
    })
    .select("*")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/messages");
  return ok(data as DirectMessage);
}

export async function deleteDirectMessage(
  id: string,
): Promise<ActionResult<void>> {
  const supabase = await createClient();

  const { error, count } = await supabase
    .from("direct_messages")
    .delete({ count: "exact" })
    .eq("id", id);

  if (error) return fail(describeDatabaseError(error));
  // RLS filters rather than refuses: a delete somebody is not allowed to make
  // removes nothing and reports no error. Without the count the two are
  // indistinguishable, and the UI would say it worked.
  if (!count) return fail("dm.notYours");

  revalidatePath("/messages");
  return ok(undefined);
}

/**
 * Move your own read marker to now.
 *
 * `user_id = auth.uid()` on the update policy is what stops this being a way
 * to clear somebody else's unread count.
 */
export async function markConversationRead(
  conversationId: string,
): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.signedOut");

  const { error } = await supabase
    .from("conversation_participants")
    .update({ last_read_at: new Date().toISOString() })
    .eq("conversation_id", conversationId)
    .eq("user_id", user.id);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/messages");
  return ok(undefined);
}

/**
 * Everyone but you, for the command palette.
 *
 * The palette searches tasks on the server because no one page holds them
 * all; people are a different shape — a handful of rows that change rarely —
 * so they come back whole once and are filtered in the browser after that.
 *
 * Row-level security decides who is on this list, same as the team page.
 */
export async function listPeople(): Promise<PersonHit[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, job_title")
    .neq("id", user.id)
    .order("full_name");

  if (error) return [];
  return (data ?? []) as PersonHit[];
}
