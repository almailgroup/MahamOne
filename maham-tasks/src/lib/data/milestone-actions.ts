"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import { isMissingTable } from "@/lib/supabase/missing";
import { describeDatabaseError, fail, ok, type ActionResult } from "@/lib/action-result";
import type { ProjectMilestone } from "@/lib/supabase/database.types";

/**
 * A project's milestones.
 *
 * Row-level security decides who may set them (planners on the project), and
 * the database keeps a task under only its own project's; neither is checked
 * again here.
 */

const id = z.string().uuid();

const milestoneSchema = z.object({
  title: z.string().trim().min(1, "milestone.titleNeeded").max(120, "milestone.titleTooLong"),
  dueOn: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "milestone.dateNeeded")
    .refine((day) => !Number.isNaN(Date.parse(`${day}T00:00:00Z`)), "milestone.dateNeeded"),
});

export type MilestoneList = {
  /** False until migration 44 has been run. */
  available: boolean;
  milestones: ProjectMilestone[];
};

/** For the task dialog, which opens anywhere a task does. */
export async function listMilestones(projectId: string): Promise<MilestoneList> {
  if (!id.safeParse(projectId).success) return { available: true, milestones: [] };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("project_milestones")
    .select("*")
    .eq("project_id", projectId)
    .order("due_on", { ascending: true });

  if (isMissingTable(error)) return { available: false, milestones: [] };
  if (error) throw new Error(error.message);
  return { available: true, milestones: data ?? [] };
}

function revalidate(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
}

export async function createMilestone(
  projectId: string,
  input: { title: string; dueOn: string },
): Promise<ActionResult<{ id: string }>> {
  if (!id.safeParse(projectId).success) return fail("db.notFound");
  const parsed = milestoneSchema.safeParse(input);
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "action.checkFields");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("project_milestones")
    .insert({ project_id: projectId, title: parsed.data.title, due_on: parsed.data.dueOn })
    .select("id")
    .single();
  if (error) return fail(describeDatabaseError(error));

  revalidate(projectId);
  return ok({ id: data.id });
}

export async function updateMilestone(
  milestoneId: string,
  projectId: string,
  input: { title: string; dueOn: string },
): Promise<ActionResult<void>> {
  if (!id.safeParse(milestoneId).success) return fail("db.notFound");
  const parsed = milestoneSchema.safeParse(input);
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "action.checkFields");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("project_milestones")
    .update({ title: parsed.data.title, due_on: parsed.data.dueOn })
    .eq("id", milestoneId)
    .select("id")
    .maybeSingle();
  if (error) return fail(describeDatabaseError(error));
  // Refused by row-level security comes back as nothing updated.
  if (!data) return fail("db.noPermission");

  revalidate(projectId);
  return ok(undefined);
}

export async function setMilestoneReached(
  milestoneId: string,
  projectId: string,
  reached: boolean,
): Promise<ActionResult<void>> {
  if (!id.safeParse(milestoneId).success) return fail("db.notFound");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("project_milestones")
    .update({ done_at: reached ? new Date().toISOString() : null })
    .eq("id", milestoneId)
    .select("id")
    .maybeSingle();
  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("db.noPermission");

  revalidate(projectId);
  return ok(undefined);
}

export async function deleteMilestone(
  milestoneId: string,
  projectId: string,
): Promise<ActionResult<void>> {
  if (!id.safeParse(milestoneId).success) return fail("db.notFound");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("project_milestones")
    .delete()
    .eq("id", milestoneId)
    .select("id");
  if (error) return fail(describeDatabaseError(error));
  if (!data || data.length === 0) return fail("db.noPermission");

  // Its tasks stay, under no milestone.
  revalidate(projectId);
  return ok(undefined);
}
