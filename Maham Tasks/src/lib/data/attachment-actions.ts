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
import { fileAttachmentSchema, linkAttachmentSchema } from "@/lib/validation";
import { ATTACHMENT_BUCKET, SIGNED_URL_TTL } from "@/lib/attachments";
import type { TaskAttachment } from "@/lib/supabase/database.types";

/**
 * Attachment mutations.
 *
 * File bytes are uploaded straight from the browser to Supabase Storage, so
 * they never pass through a Server Action (which has a small body limit). This
 * records the resulting object, and RLS decides whether the caller may.
 */

export async function addLinkAttachment(
  taskId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ id: string }>> {
  const parsed = linkAttachmentSchema.safeParse({
    name: formData.get("name"),
    url: formData.get("url"),
  });

  if (!parsed.success) {
    return fail("action.checkFields", fieldErrorsFrom(parsed.error.issues));
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  const { data, error } = await supabase
    .from("task_attachments")
    .insert({
      task_id: taskId,
      uploaded_by: user.id,
      kind: "link",
      name: parsed.data.name,
      url: parsed.data.url,
    })
    .select("id")
    .single();

  if (error) return fail(describeDatabaseError(error));

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

export async function recordFileAttachment(
  taskId: string,
  input: unknown,
): Promise<ActionResult<{ id: string }>> {
  const parsed = fileAttachmentSchema.safeParse(input);
  if (!parsed.success) return fail("action.fileNotAttached");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fail("action.sessionExpired");

  // The storage policy already checked the upload; this guards against a
  // recorded path that points at a different task's folder.
  if (!parsed.data.storagePath.startsWith(`${taskId}/`)) {
    return fail("action.fileNotThisTask");
  }

  const { data, error } = await supabase
    .from("task_attachments")
    .insert({
      task_id: taskId,
      uploaded_by: user.id,
      kind: "file",
      name: parsed.data.name,
      storage_path: parsed.data.storagePath,
      mime_type: parsed.data.mimeType ?? null,
      size_bytes: parsed.data.sizeBytes,
    })
    .select("id")
    .single();

  if (error) {
    // Nothing references the object now, so do not leave it orphaned.
    await supabase.storage
      .from(ATTACHMENT_BUCKET)
      .remove([parsed.data.storagePath]);
    return fail(describeDatabaseError(error));
  }

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

export async function deleteAttachment(
  attachmentId: string,
): Promise<ActionResult<{ id: string }>> {
  const supabase = await createClient();

  const { data: row } = await supabase
    .from("task_attachments")
    .select("id, storage_path")
    .eq("id", attachmentId)
    .maybeSingle();

  if (!row) return fail("action.attachmentGone");

  const { data, error } = await supabase
    .from("task_attachments")
    .delete()
    .eq("id", attachmentId)
    .select("id")
    .maybeSingle();

  if (error) return fail(describeDatabaseError(error));
  if (!data) return fail("action.noPermissionRemove");

  // Best effort: the row is gone either way, and a stray object is harmless.
  if (row.storage_path) {
    await supabase.storage.from(ATTACHMENT_BUCKET).remove([row.storage_path]);
  }

  revalidatePath("/", "layout");
  return ok({ id: data.id });
}

/**
 * Short-lived download URL for a stored file.
 *
 * The bucket is private, so attachments cannot be reached by guessing a path —
 * every download goes through a signed URL minted for the caller.
 */
export async function getAttachmentUrl(
  attachmentId: string,
): Promise<ActionResult<{ url: string }>> {
  const supabase = await createClient();

  const { data: row } = await supabase
    .from("task_attachments")
    .select("kind, url, storage_path")
    .eq("id", attachmentId)
    .maybeSingle<Pick<TaskAttachment, "kind" | "url" | "storage_path">>();

  if (!row) return fail("action.attachmentGone");
  if (row.kind === "link" && row.url) return ok({ url: row.url });
  if (!row.storage_path) return fail("action.attachmentNoFile");

  const { data, error } = await supabase.storage
    .from(ATTACHMENT_BUCKET)
    .createSignedUrl(row.storage_path, SIGNED_URL_TTL);

  if (error || !data) return fail("action.downloadFailed");

  return ok({ url: data.signedUrl });
}

/**
 * Short-lived addresses for a task's pictures, by attachment id, so the list
 * can show them rather than a file icon and a name like IMG_4127.JPG.
 *
 * One signing request for all of them, not one per picture. The bucket is
 * private and storage checks the task, exactly as for a download; a picture
 * this person may not read simply gets no address.
 */
export async function getAttachmentPreviews(taskId: string): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data: rows } = await supabase
    .from("task_attachments")
    .select("id, storage_path, mime_type")
    .eq("task_id", taskId)
    .eq("kind", "file")
    .like("mime_type", "image/%");

  const pictures = (rows ?? []).filter(
    (row): row is { id: string; storage_path: string; mime_type: string } =>
      Boolean(row.storage_path),
  );
  if (pictures.length === 0) return {};

  const { data, error } = await supabase.storage
    .from(ATTACHMENT_BUCKET)
    .createSignedUrls(
      pictures.map((row) => row.storage_path),
      SIGNED_URL_TTL,
    );
  if (error || !data) return {};

  const byPath = new Map(
    data.filter((one) => one.signedUrl).map((one) => [one.path, one.signedUrl]),
  );
  return Object.fromEntries(
    pictures.flatMap((row) => {
      const url = byPath.get(row.storage_path);
      return url ? [[row.id, url]] : [];
    }),
  );
}
