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
import type { Label } from "@/lib/supabase/database.types";

/**
 * Keeping the company's labels.
 *
 * Row-level security decides who may: admins and managers (labels). A refused
 * write comes back as an error and is translated, not second-guessed here.
 */

const labelSchema = z.object({
  name: z.string().trim().min(1, "label.nameRequired").max(30, "label.nameTooLong"),
  colour: z.enum(["slate", "blue", "green", "violet", "pink", "teal"]).default("slate"),
});

/** Every page that shows a task shows its labels. */
function revalidate() {
  revalidatePath("/", "layout");
}

function describe(error: { code?: string; message: string }) {
  // The unique index on the lower-cased name.
  return error.code === "23505" ? "label.exists" : describeDatabaseError(error);
}

export async function createLabel(input: {
  name: string;
  colour?: string;
}): Promise<ActionResult<Label>> {
  const parsed = labelSchema.safeParse(input);
  if (!parsed.success) return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("labels")
    .insert({ name: parsed.data.name, colour: parsed.data.colour })
    .select("*")
    .single();
  if (error) return fail(describe(error));

  revalidate();
  return ok(data);
}

export async function updateLabel(
  id: string,
  input: { name: string; colour?: string },
): Promise<ActionResult<void>> {
  if (!z.string().uuid().safeParse(id).success) return fail("label.unknown");
  const parsed = labelSchema.safeParse(input);
  if (!parsed.success) return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("labels")
    .update({ name: parsed.data.name, colour: parsed.data.colour })
    .eq("id", id)
    .select("id")
    .maybeSingle();
  if (error) return fail(describe(error));
  if (!data) return fail("label.notAllowed");

  revalidate();
  return ok(undefined);
}

/** Removes the label from every task it is on, by the foreign key. */
export async function deleteLabel(id: string): Promise<ActionResult<void>> {
  if (!z.string().uuid().safeParse(id).success) return fail("label.unknown");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("labels")
    .delete()
    .eq("id", id)
    .select("id")
    .maybeSingle();
  if (error) return fail(describe(error));
  if (!data) return fail("label.notAllowed");

  revalidate();
  return ok(undefined);
}
