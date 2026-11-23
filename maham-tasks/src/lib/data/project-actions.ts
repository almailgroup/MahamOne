"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import {
  describeDatabaseError,
  fail,
  fieldErrorsFrom,
  ok,
  type ActionResult,
} from "@/lib/action-result";
import { projectSchema } from "@/lib/validation";

/**
 * Project mutations.
 *
 * Authorisation is left to Row Level Security — these actions do not re-check
 * roles. A denied write comes back as a Postgres error, which is translated
 * into a message for the form. That way there is exactly one source of truth
 * for who may do what.
 */

async function requireUserId() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, userId: user?.id ?? null };
}

export async function createProject(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ id: string }>> {
  const parsed = projectSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") ?? undefined,
  });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const { supabase, userId } = await requireUserId();
  if (!userId) return fail("action.sessionExpired");

  const { data, error } = await supabase
    .from("projects")
    .insert({
      name: parsed.data.name,
      description: parsed.data.description || null,
      created_by: userId,
    })
    .select("id")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

export async function updateProject(
  projectId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ id: string }>> {
  const parsed = projectSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") ?? undefined,
  });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("projects")
    .update({
      name: parsed.data.name,
      description: parsed.data.description || null,
    })
    .eq("id", projectId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  // No row came back: RLS filtered the update out rather than erroring.
  if (!data) return fail("action.noPermissionEditProject");

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

export async function deleteProject(
  projectId: string,
): Promise<ActionResult<{ id: string }>> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("projects")
    .delete()
    .eq("id", projectId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noPermissionDeleteProject");

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

/**
 * Project membership.
 *
 * Membership is what makes a project visible, so these are restricted to
 * managers and admins by RLS. Assigning someone a task in a project also adds
 * them automatically, which is handled by a database trigger rather than here.
 */

export async function addProjectMember(
  projectId: string,
  userId: string,
): Promise<ActionResult<void>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error } = await supabase
    .from("project_members")
    .insert({ project_id: projectId, user_id: userId, added_by: user.id });

  // Already a member: nothing to do, and not worth an error.
  if (error && error.code !== "23505") {
    return fail(describeDatabaseError(error));
  }

  revalidatePath("/", "layout");
  return ok(undefined);
}

export async function removeProjectMember(
  projectId: string,
  userId: string,
): Promise<ActionResult<void>> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("project_members")
    .delete()
    .eq("project_id", projectId)
    .eq("user_id", userId)
    .select("user_id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));

  // Nothing came back, which means one of two very different things: RLS
  // refused the delete, or the row had already gone. Look before blaming the
  // caller — reporting "no permission" for work that is already done is how a
  // harmless double-click turns into an error the user cannot act on.
  if (!data) {
    const { data: still } = await supabase
      .from("project_members")
      .select("user_id")
      .eq("project_id", projectId)
      .eq("user_id", userId)
      .maybeSingle();

    if (still) return fail("action.noPermissionMembership");
  }

  revalidatePath("/", "layout");
  return ok(undefined);
}

/**
 * Put a project away, or bring it back.
 *
 * Archiving hides a project from the sidebar and every picker without
 * touching a single row of its work: its tasks, comments and history stay
 * exactly where they were, and opening the project still shows them.
 *
 * Refused while anything in it is still open, which is the difference
 * between finishing a project and losing track of one. The count comes back
 * in the message so the person knows what is left rather than being told
 * "no".
 */
export async function setProjectArchived(
  projectId: string,
  archived: boolean,
): Promise<ActionResult<void>> {
  const supabase = await createClient();

  const { error } = await supabase.rpc("set_project_archived", {
    project: projectId,
    archived,
  });

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/dashboard");
  revalidatePath("/tasks");
  revalidatePath(`/projects/${projectId}`);
  return ok(undefined);
}
