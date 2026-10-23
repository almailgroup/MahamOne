"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import { isMissingTable } from "@/lib/supabase/missing";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * Which tasks wait on which.
 *
 * Row-level security decides who may link them (planners, between tasks they
 * can see) and the database refuses a circle; neither is checked again here.
 */

export type TaskRef = { id: string; title: string; status: TaskStatus };

export type TaskDependencies = {
  /** False until migration 40 has been run: the panel stays out of the way. */
  available: boolean;
  /** What this task cannot start without. */
  waitingOn: TaskRef[];
  /** What is waiting for this task to be finished. */
  holdingUp: TaskRef[];
};

const id = z.string().uuid();

type Embedded = { id: string; title: string; status: TaskStatus } | null;

export async function listTaskDependencies(taskId: string): Promise<TaskDependencies> {
  const none: TaskDependencies = { available: true, waitingOn: [], holdingUp: [] };
  if (!id.safeParse(taskId).success) return none;

  const supabase = await createClient();
  const [waiting, holding] = await Promise.all([
    supabase
      .from("task_dependencies")
      .select("blocked_by, task:tasks!task_dependencies_blocked_by_fkey(id, title, status)")
      .eq("task_id", taskId),
    supabase
      .from("task_dependencies")
      .select("task_id, task:tasks!task_dependencies_task_id_fkey(id, title, status)")
      .eq("blocked_by", taskId),
  ]);

  if (isMissingTable(waiting.error)) return { ...none, available: false };
  if (waiting.error) throw new Error(waiting.error.message);
  if (holding.error) throw new Error(holding.error.message);

  // A task this person cannot see comes back as null and is left out: a
  // name they are not allowed to read is not worth a row saying so.
  const tasks = (rows: { task: unknown }[] | null) =>
    (rows ?? [])
      .map((row) => row.task as Embedded)
      .filter((task): task is TaskRef => task !== null)
      .sort((a, b) => Number(a.status === "done") - Number(b.status === "done"));

  return { available: true, waitingOn: tasks(waiting.data), holdingUp: tasks(holding.data) };
}

function revalidate() {
  // The waiting count rides on every task in every list.
  revalidatePath("/", "layout");
}

export async function addTaskDependency(
  taskId: string,
  blockedBy: string,
): Promise<ActionResult<void>> {
  if (!id.safeParse(taskId).success || !id.safeParse(blockedBy).success) {
    return fail("dependency.unknownTask");
  }
  if (taskId === blockedBy) return fail("dependency.itself");

  const supabase = await createClient();
  const { error } = await supabase
    .from("task_dependencies")
    .insert({ task_id: taskId, blocked_by: blockedBy });

  if (error) {
    if (error.message.includes("task.dependencyCycle")) return fail("dependency.cycle");
    // Already linked: what was asked for is true.
    if (error.code === "23505") return ok(undefined);
    return fail(describeDatabaseError(error));
  }

  revalidate();
  return ok(undefined);
}

export async function removeTaskDependency(
  taskId: string,
  blockedBy: string,
): Promise<ActionResult<void>> {
  if (!id.safeParse(taskId).success || !id.safeParse(blockedBy).success) {
    return fail("dependency.unknownTask");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("task_dependencies")
    .delete()
    .eq("task_id", taskId)
    .eq("blocked_by", blockedBy);
  if (error) return fail(describeDatabaseError(error));

  revalidate();
  return ok(undefined);
}
