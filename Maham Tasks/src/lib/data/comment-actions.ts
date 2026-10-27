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
import { commentSchema } from "@/lib/validation";
import { isReaction } from "@/lib/reactions";

export async function postComment(
  taskId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ id: string }>> {
  const parsed = commentSchema.safeParse({ content: formData.get("content") });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return fail("action.sessionExpired");

  const { data, error } = await supabase
    .from("comments")
    .insert({
      task_id: taskId,
      user_id: user.id,
      content: parsed.data.content,
    })
    .select("id")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/dashboard");
  return ok({ id: data.id });
}

export async function deleteComment(
  commentId: string,
): Promise<ActionResult<{ id: string }>> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("comments")
    .delete()
    .eq("id", commentId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noPermissionDeleteComment");

  return ok({ id: data.id });
}

/**
 * Add the caller's reaction to a comment, or take it back if it is there.
 *
 * One action for both, because that is what a tap on a chip means. The
 * delete is tried first: it either removes the caller's own row or matches
 * nothing, and either answer says what to do next. Row-level security
 * decides whether they could see the comment to react to at all.
 */
export async function toggleReaction(
  commentId: string,
  emoji: string,
): Promise<ActionResult<{ reacted: boolean }>> {
  if (!isReaction(emoji)) return fail("reaction.unknown");
  if (!z.string().uuid().safeParse(commentId).success) return fail("db.notFound");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { error: removeError, count } = await supabase
    .from("comment_reactions")
    .delete({ count: "exact" })
    .eq("comment_id", commentId)
    .eq("user_id", user.id)
    .eq("emoji", emoji);

  if (removeError) return fail(describeDatabaseError(removeError));
  if (count) return ok({ reacted: false });

  const { error } = await supabase
    .from("comment_reactions")
    .insert({ comment_id: commentId, user_id: user.id, emoji });

  // Two taps racing each other both found nothing to remove; the second
  // insert then collides with the first. The reaction is there, which is
  // what was asked for.
  if (error && error.code !== "23505") return fail(describeDatabaseError(error));

  return ok({ reacted: true });
}
