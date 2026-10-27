"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { ChecklistItem } from "@/lib/supabase/database.types";

/**
 * The steps inside a task.
 *
 * None of these check anything themselves. Row-level security decides who
 * may add, tick or remove a step, under exactly the rules the task itself
 * has — so a refusal arrives as a row that did not change rather than as a
 * permission check written twice, once here and once in the database, which
 * is how the two drift apart.
 */

/** Gaps, so an item can be dropped between two without renumbering. */
const STEP = 1024;

export async function addChecklistItem(
  taskId: string,
  content: string,
): Promise<ActionResult<ChecklistItem>> {
  const trimmed = content.trim();
  if (!trimmed) return fail("checklist.empty");
  if (trimmed.length > 500) return fail("checklist.tooLong");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  // After the last one, without asking for the whole list.
  const { data: last } = await supabase
    .from("task_checklist_items")
    .select("position")
    .eq("task_id", taskId)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();

  const { data, error } = await supabase
    .from("task_checklist_items")
    .insert({
      task_id: taskId,
      content: trimmed,
      position: (last?.position ?? 0) + STEP,
      created_by: user.id,
    })
    .select("*")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("checklist.noPermission");

  revalidatePath("/tasks");
  return ok(data as ChecklistItem);
}

export async function setChecklistItemDone(
  itemId: string,
  done: boolean,
): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("task_checklist_items")
    .update({ done })
    .eq("id", itemId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  // No row came back: row-level security filtered it rather than refusing,
  // which is the same answer stated more quietly.
  if (!data) return fail("checklist.noPermission");

  revalidatePath("/tasks");
  return ok(undefined);
}

export async function renameChecklistItem(
  itemId: string,
  content: string,
): Promise<ActionResult<void>> {
  const trimmed = content.trim();
  if (!trimmed) return fail("checklist.empty");
  if (trimmed.length > 500) return fail("checklist.tooLong");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("task_checklist_items")
    .update({ content: trimmed })
    .eq("id", itemId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("checklist.noPermission");

  revalidatePath("/tasks");
  return ok(undefined);
}

export async function removeChecklistItem(itemId: string): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const { error, count } = await supabase
    .from("task_checklist_items")
    .delete({ count: "exact" })
    .eq("id", itemId);

  if (error) return fail(describeDatabaseError(error));
  // A delete that removed nothing was refused by row-level security; the
  // count is the only way to tell the two apart.
  if ((count ?? 0) === 0) return fail("checklist.noPermission");

  revalidatePath("/tasks");
  return ok(undefined);
}

/**
 * The steps of one task, for the panel that shows them.
 *
 * Fetched when the dialog opens rather than carried on the task: a board of
 * forty tasks needs forty counts, not forty lists, and the counts ride along
 * with the task already.
 */
export async function listChecklistItems(taskId: string): Promise<ChecklistItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("task_checklist_items")
    .select("*")
    .eq("task_id", taskId)
    .order("position", { ascending: true });

  if (error) return [];
  return (data ?? []) as ChecklistItem[];
}
