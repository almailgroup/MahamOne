"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createClient } from "@/lib/supabase/server";
import {
  describeDatabaseError,
  fail,
  fieldErrorsFrom,
  ok,
  type ActionResult,
} from "@/lib/action-result";

/**
 * Saying how a project is going.
 *
 * Row-level security decides who may: managers and admins on the project,
 * as themselves. Nothing here checks a role — a refused insert comes back as
 * an error, and is translated rather than second-guessed.
 */

const statusSchema = z.object({
  status: z.enum(["on_track", "at_risk", "off_track"], {
    errorMap: () => ({ message: "health.unknownStatus" }),
  }),
  body: z
    .string()
    .trim()
    .min(1, "health.bodyRequired")
    .max(2000, "health.bodyTooLong"),
});

const uuid = z.string().uuid();

function revalidateProject(projectId: string) {
  revalidatePath(`/projects/${projectId}`);
  // The dashboard's "needs attention" is made of these.
  revalidatePath("/dashboard");
}

export async function postStatusUpdate(
  projectId: string,
  input: { status: string; body: string },
): Promise<ActionResult<{ id: string }>> {
  if (!uuid.safeParse(projectId).success) return fail("db.notFound");

  const parsed = statusSchema.safeParse(input);
  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { data, error } = await supabase
    .from("project_status_updates")
    .insert({
      project_id: projectId,
      author_id: user.id,
      status: parsed.data.status,
      body: parsed.data.body,
    })
    .select("id")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidateProject(projectId);
  return ok({ id: data.id });
}

export async function withdrawStatusUpdate(
  id: string,
  projectId: string,
): Promise<ActionResult<void>> {
  if (!uuid.safeParse(id).success) return fail("db.notFound");

  const supabase = await createClient();
  const { error, count } = await supabase
    .from("project_status_updates")
    .delete({ count: "exact" })
    .eq("id", id);

  if (error) return fail(describeDatabaseError(error));
  // Row-level security filters rather than refuses: a delete somebody may
  // not make removes nothing and reports no error.
  if (!count) return fail("health.notYours");

  revalidateProject(projectId);
  return ok(undefined);
}
