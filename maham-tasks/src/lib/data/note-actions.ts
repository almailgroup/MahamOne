"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import {
  describeDatabaseError,
  fail,
  ok,
  type ActionResult,
} from "@/lib/action-result";
import type { PersonalNote, PersonalNoteItem } from "@/lib/supabase/database.types";

/**
 * My List — personal note mutations.
 *
 * Every statement is scoped to the caller's own rows by RLS, so none of these
 * carry a user filter of their own beyond the owner column an insert has to
 * set. A write that touches somebody else's note comes back as zero rows,
 * which is reported as a permission failure rather than a crash.
 */

/** Gap between adjacent checklist items, so inserts between two stay exact. */
const POSITION_STEP = 1024;

const uuid = z.string().uuid();
const titleSchema = z.string().trim().max(200);
const bodySchema = z.string().max(20_000);
const contentSchema = z.string().max(1000);

async function currentUserId(
  supabase: Awaited<ReturnType<typeof createClient>>,
): Promise<string | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}

export async function createNote(
  title = "",
): Promise<ActionResult<PersonalNote>> {
  const parsed = titleSchema.safeParse(title);
  if (!parsed.success) return fail("action.titleTooLong");

  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return fail("action.sessionExpired");

  const { data, error } = await supabase
    .from("personal_notes")
    .insert({ user_id: userId, title: parsed.data })
    .select("*")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/my-list");
  return ok(data as PersonalNote);
}

/** Save a note's title and body. Called on a debounce as the user types. */
export async function saveNote(
  noteId: string,
  input: { title: string; body: string },
): Promise<ActionResult<{ updatedAt: string }>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");

  const title = titleSchema.safeParse(input.title);
  const body = bodySchema.safeParse(input.body);
  if (!title.success) return fail("action.titleUnder200");
  if (!body.success) return fail("action.noteTooLong");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("personal_notes")
    .update({ title: title.data, body: body.data })
    .eq("id", noteId)
    .select("updated_at")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noteGone");

  revalidatePath("/my-list");
  return ok({ updatedAt: data.updated_at });
}

export async function setNotePinned(
  noteId: string,
  pinned: boolean,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("personal_notes")
    .update({ pinned })
    .eq("id", noteId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noteGone");

  revalidatePath("/my-list");
  return ok(undefined);
}

export async function deleteNote(
  noteId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("personal_notes")
    .delete()
    .eq("id", noteId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noteGone");

  revalidatePath("/my-list");
  return ok(undefined);
}

/**
 * Append a checklist item.
 *
 * The position is read back from the note's own items rather than counted on
 * the client, so two devices adding at once cannot land on the same slot.
 */
export async function addNoteItem(
  noteId: string,
  content = "",
): Promise<ActionResult<PersonalNoteItem>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");
  const parsed = contentSchema.safeParse(content);
  if (!parsed.success) return fail("action.lineTooLong");

  const supabase = await createClient();
  const userId = await currentUserId(supabase);
  if (!userId) return fail("action.sessionExpired");

  const { data: last } = await supabase
    .from("personal_note_items")
    .select("position")
    .eq("note_id", noteId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();

  const { data, error } = await supabase
    .from("personal_note_items")
    .insert({
      note_id: noteId,
      user_id: userId,
      content: parsed.data,
      position: (last?.position ?? 0) + POSITION_STEP,
    })
    .select("*")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/my-list");
  return ok(data as PersonalNoteItem);
}

export async function updateNoteItem(
  itemId: string,
  input: { content?: string; done?: boolean },
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(itemId).success) return fail("action.unknownItem");

  const patch: { content?: string; done?: boolean } = {};

  if (input.content !== undefined) {
    const parsed = contentSchema.safeParse(input.content);
    if (!parsed.success) return fail("action.lineTooLong");
    patch.content = parsed.data;
  }
  if (input.done !== undefined) patch.done = input.done;
  if (Object.keys(patch).length === 0) return ok(undefined);

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("personal_note_items")
    .update(patch)
    .eq("id", itemId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.lineGone");

  revalidatePath("/my-list");
  return ok(undefined);
}

export async function deleteNoteItem(
  itemId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(itemId).success) return fail("action.unknownItem");

  const supabase = await createClient();
  const { error } = await supabase
    .from("personal_note_items")
    .delete()
    .eq("id", itemId);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/my-list");
  return ok(undefined);
}

/** Clear every ticked line — the "start tomorrow fresh" button. */
export async function clearDoneItems(
  noteId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");

  const supabase = await createClient();
  const { error } = await supabase
    .from("personal_note_items")
    .delete()
    .eq("note_id", noteId)
    .eq("done", true);

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/my-list");
  return ok(undefined);
}

/**
 * Sharing a list.
 *
 * Who may do what is decided by the policies in migration 0019, not here: the
 * owner invites and removes, a collaborator may remove only themselves, and a
 * write that is not allowed comes back as zero rows rather than an error. Each
 * of these reports that as a permission failure.
 */

export async function shareNote(
  noteId: string,
  userId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");
  if (!uuid.safeParse(userId).success) return fail("action.unknownPerson");

  const supabase = await createClient();
  const currentId = await currentUserId(supabase);
  if (!currentId) return fail("action.sessionExpired");
  if (currentId === userId) return fail("action.listAlreadyYours");

  const { error } = await supabase
    .from("personal_note_shares")
    .insert({ note_id: noteId, user_id: userId, added_by: currentId });

  // Already shared: nothing to do, and not worth an error.
  if (error && error.code !== "23505") {
    if (error.code === "42501") {
      return fail("action.onlyOwnerShares");
    }
    // The table arrives with migration 0019. Until it is applied, say which
    // step is missing rather than reporting a relation nobody has heard of.
    if (error.code === "42P01" || error.code === "PGRST205") {
      return fail(
        "action.sharingNotSetUp",
      );
    }
    return fail(describeDatabaseError(error));
  }

  revalidatePath("/my-list");
  return ok(undefined);
}

/** Remove somebody from a list. Passing your own id is how you leave one. */
export async function unshareNote(
  noteId: string,
  userId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(noteId).success) return fail("action.unknownNote");
  if (!uuid.safeParse(userId).success) return fail("action.unknownPerson");

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("personal_note_shares")
    .delete()
    .eq("note_id", noteId)
    .eq("user_id", userId)
    .select("user_id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));

  // Nothing came back: either the policy refused, or they were already off the
  // list. Look before blaming the caller.
  if (!data) {
    const { data: still } = await supabase
      .from("personal_note_shares")
      .select("user_id")
      .eq("note_id", noteId)
      .eq("user_id", userId)
      .maybeSingle();

    if (still) return fail("action.onlyOwnerRemoves");
  }

  revalidatePath("/my-list");
  return ok(undefined);
}
