"use server";

import { z } from "zod";

import { createTask, changeTaskStatus, rescheduleTask } from "@/lib/data/task-actions";
import { createClient } from "@/lib/supabase/server";
import { fail, ok, type ActionResult } from "@/lib/action-result";
import {
  taskPrioritySchema,
  taskStatusSchema,
} from "@/lib/validation";
import type { AssistantAction } from "@/lib/assistant/types";

/**
 * Carrying out something the assistant proposed, once a person has agreed.
 *
 * Two things make this safe, and neither is the model's good behaviour.
 *
 * Nothing here talks to the database on its own terms: every branch hands off
 * to the Server Action the ordinary buttons already call, so row-level
 * security, the review gate and the role checks all apply exactly as they do
 * to a click. The assistant cannot reach past what the person asking could do
 * by hand, because it is not taking a different path to the data.
 *
 * And nothing that arrives is trusted. This is a Server Action, so anybody
 * signed in can call it with anything at all — a language model is only the
 * likeliest source of a strange payload, not the only one. Every field is
 * parsed before it is used, and an id that is not a uuid never reaches a
 * query. That the proposal came back through our own Worker buys it nothing.
 */

const uuid = z.string().uuid();

const createTaskArgs = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(20_000).optional(),
  projectId: uuid.nullish(),
  assigneeIds: z.array(uuid).max(20).optional(),
  /** An absolute instant; the model is told to resolve the reader's clock. */
  dueAt: z.string().datetime({ offset: true }).optional(),
  priority: taskPrioritySchema.optional(),
  status: taskStatusSchema.optional(),
});

const setStatusArgs = z.object({
  taskId: uuid,
  status: taskStatusSchema,
});

const rescheduleArgs = z.object({
  taskId: uuid,
  dueAt: z.string().datetime({ offset: true }).nullish(),
});

/** Which project a task belongs to, for cache invalidation after the write. */
async function projectOf(taskId: string): Promise<string | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("tasks")
    .select("project_id")
    .eq("id", taskId)
    .maybeSingle();
  return data?.project_id ?? null;
}

export async function runAssistantAction(
  action: AssistantAction,
): Promise<ActionResult<void>> {
  switch (action.name) {
    case "create_task": {
      const parsed = createTaskArgs.safeParse(action.arguments);
      if (!parsed.success) return fail("assistant.badProposal");

      const form = new FormData();
      form.set("title", parsed.data.title);
      if (parsed.data.description) form.set("description", parsed.data.description);
      form.set("status", parsed.data.status ?? "todo");
      form.set("priority", parsed.data.priority ?? "medium");
      if (parsed.data.dueAt) form.set("dueAt", parsed.data.dueAt);
      for (const id of parsed.data.assigneeIds ?? []) form.append("assigneeIds", id);

      const outcome = await createTask(parsed.data.projectId ?? null, null, form);
      return outcome.ok ? ok(undefined) : outcome;
    }

    case "set_task_status": {
      const parsed = setStatusArgs.safeParse(action.arguments);
      if (!parsed.success) return fail("assistant.badProposal");

      const outcome = await changeTaskStatus(
        parsed.data.taskId,
        await projectOf(parsed.data.taskId),
        parsed.data.status,
      );
      return outcome.ok ? ok(undefined) : outcome;
    }

    case "reschedule_task": {
      const parsed = rescheduleArgs.safeParse(action.arguments);
      if (!parsed.success) return fail("assistant.badProposal");

      const outcome = await rescheduleTask(
        parsed.data.taskId,
        await projectOf(parsed.data.taskId),
        parsed.data.dueAt ?? null,
      );
      return outcome.ok ? ok(undefined) : outcome;
    }

    default:
      // A tool this version does not know about. The model was told the three
      // it has; anything else is a mistake, and running nothing is the right
      // answer to a mistake.
      return fail("assistant.unknownAction");
  }
}
