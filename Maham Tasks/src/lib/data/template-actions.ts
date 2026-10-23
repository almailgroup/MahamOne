"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import { isMissingTable } from "@/lib/supabase/missing";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { TaskTemplate } from "@/lib/supabase/database.types";

/**
 * Task templates: work that comes round again, kept so the next one starts
 * with its steps already written.
 *
 * Row-level security decides who may keep them (admins and managers).
 */

const id = z.string().uuid();

/** Every template, by name. Empty, quietly, before migration 41. */
export async function listTemplates(): Promise<TaskTemplate[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("task_templates").select("*").order("name");
  if (error) {
    if (!isMissingTable(error)) console.error(`[templates] list: ${error.message}`);
    return [];
  }
  return data ?? [];
}

/**
 * Keep a task as a template: its title, description, priority, labels and
 * the text of its steps — not who it is for or when, which belong to this
 * occurrence, not to the work.
 */
export async function saveTaskAsTemplate(taskId: string): Promise<ActionResult<TaskTemplate>> {
  if (!id.safeParse(taskId).success) return fail("template.unknownTask");

  const supabase = await createClient();
  const [task, steps, labels] = await Promise.all([
    supabase.from("tasks").select("title, description, priority").eq("id", taskId).maybeSingle(),
    supabase.from("task_checklist_items").select("content").eq("task_id", taskId).order("position"),
    supabase.from("task_labels").select("label_id").eq("task_id", taskId),
  ]);
  if (task.error) return fail(describeDatabaseError(task.error));
  if (!task.data) return fail("template.unknownTask");

  const { data, error } = await supabase
    .from("task_templates")
    .insert({
      name: task.data.title.slice(0, 80),
      title: task.data.title,
      description: task.data.description,
      priority: task.data.priority,
      steps: (steps.data ?? []).map((step) => step.content).slice(0, 50),
      // Before migration 39 there are no labels to keep.
      label_ids: (labels.data ?? []).map((label) => label.label_id),
    })
    .select("*")
    .single();
  if (error) return fail(isMissingTable(error) ? "template.notYet" : describeDatabaseError(error));

  revalidatePath("/settings");
  return ok(data);
}

const editSchema = z.object({
  name: z.string().trim().min(1, "template.nameRequired").max(80, "template.nameTooLong"),
  dueInWorkingDays: z.number().int().min(0).max(365).nullable(),
});

export async function updateTemplate(
  templateId: string,
  input: { name: string; dueInWorkingDays: number | null },
): Promise<ActionResult<void>> {
  if (!id.safeParse(templateId).success) return fail("template.unknown");
  const parsed = editSchema.safeParse(input);
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "action.checkFields");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("task_templates")
    .update({ name: parsed.data.name, due_in_working_days: parsed.data.dueInWorkingDays })
    .eq("id", templateId)
    .select("id")
    .maybeSingle();
  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("template.notAllowed");

  revalidatePath("/settings");
  return ok(undefined);
}

export async function deleteTemplate(templateId: string): Promise<ActionResult<void>> {
  if (!id.safeParse(templateId).success) return fail("template.unknown");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("task_templates")
    .delete()
    .eq("id", templateId)
    .select("id")
    .maybeSingle();
  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("template.notAllowed");

  revalidatePath("/settings");
  return ok(undefined);
}
