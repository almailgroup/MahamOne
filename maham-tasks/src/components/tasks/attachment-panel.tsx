"use client";

import * as React from "react";
import {
  Camera,
  ExternalLink,
  File as FileIcon,
  ImagePlus,
  Link2,
  Loader2,
  Paperclip,
  Trash2,
  Upload,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import {
  addLinkAttachment,
  deleteAttachment,
  getAttachmentPreviews,
  getAttachmentUrl,
  recordFileAttachment,
} from "@/lib/data/attachment-actions";
import {
  ATTACHMENT_BUCKET,
  MAX_ATTACHMENT_BYTES,
  attachmentPath,
  formatBytes,
  linkHost,
} from "@/lib/attachments";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";
import { useI18n } from "@/lib/i18n/client";
import type { Profile, TaskAttachment } from "@/lib/supabase/database.types";

/**
 * A pasted screenshot arrives as "image.png", every time; give it a name a
 * list of them can be told apart by.
 */
function named(file: File, screenshot: string): File {
  if (file.name && file.name !== "image.png") return file;
  const stamp = new Date().toISOString().slice(0, 16).replace("T", " ").replace(":", ".");
  const extension = file.type.split("/")[1] ?? "png";
  return new File([file], `${screenshot} ${stamp}.${extension}`, { type: file.type });
}

/**
 * Files and links attached to a task.
 *
 * File bytes go straight from the browser to Supabase Storage — a Server
 * Action body is far too small for real attachments — and only the resulting
 * metadata is recorded through an action.
 *
 * Files arrive four ways: picked, photographed with the phone's camera,
 * dropped onto the panel, or pasted — a screenshot straight from the
 * clipboard. Pictures show as pictures, and open full size here rather than
 * in a new tab.
 */
export function AttachmentPanel({
  taskId,
  currentProfile,
}: {
  taskId: string;
  currentProfile: Profile;
}) {
  const supabase = React.useMemo(() => createClient(), []);
  const { t, tm } = useI18n();
  const fileInput = React.useRef<HTMLInputElement>(null);
  const cameraInput = React.useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = React.useState(false);
  /** Short-lived addresses for the pictures, by attachment id. */
  const [previews, setPreviews] = React.useState<Record<string, string>>({});
  const [viewing, setViewing] = React.useState<TaskAttachment | null>(null);

  const [items, setItems] = React.useState<TaskAttachment[] | null>(null);
  const [uploading, setUploading] = React.useState(false);
  const [showLinkForm, setShowLinkForm] = React.useState(false);
  const [savingLink, setSavingLink] = React.useState(false);
  const [opening, setOpening] = React.useState<string | null>(null);

  const load = React.useCallback(async () => {
    const { data, error } = await supabase
      .from("task_attachments")
      .select("*")
      .eq("task_id", taskId)
      .order("created_at", { ascending: false });

    if (error) {
      toast.error(t("attach.loadFailed"));
      setItems([]);
      return;
    }
    setItems(data ?? []);
    if ((data ?? []).some((item) => item.mime_type?.startsWith("image/"))) {
      setPreviews(await getAttachmentPreviews(taskId).catch(() => ({})));
    }
  }, [supabase, taskId, t]);

  React.useEffect(() => {
    load();
  }, [load]);

  async function onFilesPicked(event: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? []);
    // Let the same file be picked again after a failure.
    event.target.value = "";
    await upload(files);
  }

  function onDrop(event: React.DragEvent) {
    event.preventDefault();
    setDragging(false);
    void upload(Array.from(event.dataTransfer.files));
  }

  function onPaste(event: React.ClipboardEvent) {
    const files = Array.from(event.clipboardData.files);
    if (files.length === 0) return;
    event.preventDefault();
    void upload(files.map((file) => named(file, t("attach.screenshot"))));
  }

  async function upload(files: File[]) {
    if (files.length === 0 || uploading) return;

    setUploading(true);

    for (const file of files) {
      if (file.size > MAX_ATTACHMENT_BYTES) {
        toast.error(
          t("attach.tooBig", {
            name: file.name,
            size: formatBytes(file.size),
            limit: formatBytes(MAX_ATTACHMENT_BYTES),
          }),
        );
        continue;
      }

      const path = attachmentPath(taskId, file.name);

      const { error: uploadError } = await supabase.storage
        .from(ATTACHMENT_BUCKET)
        .upload(path, file, { cacheControl: "3600", upsert: false });

      if (uploadError) {
        toast.error(t("attach.uploadFailed", { name: file.name }));
        continue;
      }

      const outcome = await recordFileAttachment(taskId, {
        name: file.name,
        storagePath: path,
        mimeType: file.type || undefined,
        sizeBytes: file.size,
      });

      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        continue;
      }
    }

    setUploading(false);
    await load();
  }

  async function onAddLink(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSavingLink(true);

    const form = event.currentTarget;
    const outcome = await addLinkAttachment(taskId, null, new FormData(form));
    setSavingLink(false);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }

    form.reset();
    setShowLinkForm(false);
    await load();
  }

  async function open(attachment: TaskAttachment) {
    if (attachment.kind === "link" && attachment.url) {
      window.open(attachment.url, "_blank", "noopener,noreferrer");
      return;
    }

    // A picture opens here, full size, rather than in a new tab.
    if (previews[attachment.id]) {
      setViewing(attachment);
      return;
    }

    // The bucket is private, so mint a short-lived signed URL on demand.
    setOpening(attachment.id);
    const outcome = await getAttachmentUrl(attachment.id);
    setOpening(null);

    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    window.open(outcome.data.url, "_blank", "noopener,noreferrer");
  }

  async function remove(attachment: TaskAttachment) {
    const outcome = await deleteAttachment(attachment.id);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setItems((current) =>
      current ? current.filter((a) => a.id !== attachment.id) : current,
    );
  }

  const canRemove = (a: TaskAttachment) =>
    a.uploaded_by === currentProfile.id ||
    currentProfile.role === "admin" ||
    currentProfile.role === "manager";

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <input
          ref={fileInput}
          type="file"
          multiple
          hidden
          onChange={onFilesPicked}
          data-testid="attach-files"
        />
        {/* The phone's camera, straight to a photo: a receipt, a signed page. */}
        <input
          ref={cameraInput}
          type="file"
          accept="image/*"
          capture="environment"
          hidden
          onChange={onFilesPicked}
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => fileInput.current?.click()}
          disabled={uploading}
        >
          {uploading ? <Loader2 className="animate-spin" /> : <Upload />}
          {uploading ? t("attach.uploading") : t("attach.upload")}
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => cameraInput.current?.click()}
          disabled={uploading}
          // Where there is a camera to hand: a phone, a tablet.
          className="hidden max-sm:inline-flex pointer-coarse:inline-flex"
        >
          <Camera />
          {t("attach.takePhoto")}
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => setShowLinkForm((open) => !open)}
        >
          <Link2 />
          {t("attach.addLink")}
        </Button>
        <span className="text-xs text-muted-foreground">
          {t("attach.limit", { limit: formatBytes(MAX_ATTACHMENT_BYTES) })}
        </span>
      </div>

      {showLinkForm && (
        <form
          onSubmit={onAddLink}
          className="flex flex-col gap-2 rounded-xl bg-foreground/[0.05] p-3"
        >
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="attachment-name">{t("attach.label")}</Label>
            <Input
              id="attachment-name"
              name="name"
              placeholder={t("attach.labelPlaceholder")}
              maxLength={255}
              required
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="attachment-url">{t("attach.url")}</Label>
            <Input
              id="attachment-url"
              name="url"
              type="url"
              placeholder="https://..."
              required
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => setShowLinkForm(false)}
            >
              {t("common.cancel")}
            </Button>
            <Button type="submit" size="sm" disabled={savingLink}>
              {savingLink && <Loader2 className="animate-spin" />}
              {t("attach.addLink")}
            </Button>
          </div>
        </form>
      )}

      {/* Drop files here, or click it and paste. A screenshot is the commonest
          attachment there is, and saving one to a file first only to pick
          it again was three steps too many. */}
      <div
        role="button"
        tabIndex={0}
        aria-label={t("attach.dropHere")}
        onDragOver={(event) => {
          event.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onPaste={onPaste}
        onClick={(event) => event.currentTarget.focus()}
        className={cn(
          "flex items-center justify-center gap-2 rounded-[1.25rem] px-4 py-3.5 text-center text-xs text-muted-foreground transition-colors max-sm:hidden",
          "bg-foreground/[0.035] focus-visible:bg-primary/[0.07] focus-visible:text-foreground focus-visible:outline-none",
          dragging && "bg-primary/[0.1] text-foreground",
        )}
      >
        <ImagePlus className="size-4 shrink-0" aria-hidden />
        {dragging ? t("attach.dropNow") : t("attach.dropHere")}
      </div>

      {items === null ? (
        <div className="flex flex-col gap-2">
          <Skeleton className="h-9 w-full" />
          <Skeleton className="h-9 w-2/3" />
        </div>
      ) : items.length === 0 ? (
        <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Paperclip className="size-3.5" />
          {t("attach.empty")}
        </p>
      ) : (
        <ul className="flex flex-col gap-1.5">
          {items.map((attachment) => (
            <li
              key={attachment.id}
              className="flex items-center gap-2 rounded-xl bg-foreground/[0.05] px-2.5 py-2"
            >
              {previews[attachment.id] ? (
                // eslint-disable-next-line @next/next/no-img-element -- a signed, short-lived storage address
                <img
                  src={previews[attachment.id]}
                  alt=""
                  className="size-10 shrink-0 rounded-xl bg-muted object-cover"
                  loading="lazy"
                />
              ) : attachment.kind === "link" ? (
                <Link2 className="size-4 shrink-0 text-muted-foreground" />
              ) : (
                <FileIcon className="size-4 shrink-0 text-muted-foreground" />
              )}

              <button
                type="button"
                onClick={() => open(attachment)}
                className="min-w-0 flex-1 text-start focus-visible:outline-none"
              >
                <span className="block truncate text-sm font-medium">
                  {attachment.name}
                </span>
                <span className="block truncate text-xs text-muted-foreground">
                  {attachment.kind === "link"
                    ? linkHost(attachment.url ?? "")
                    : formatBytes(attachment.size_bytes)}
                </span>
              </button>

              {opening === attachment.id ? (
                <Loader2 className="size-4 animate-spin text-muted-foreground" />
              ) : (
                <ExternalLink className="size-3.5 shrink-0 text-muted-foreground" />
              )}

              {canRemove(attachment) && (
                <Button
                  variant="ghost"
                  size="icon-sm"
                  onClick={() => remove(attachment)}
                  aria-label={t("assign.remove", { name: attachment.name })}
                >
                  <Trash2 />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      <Dialog open={viewing !== null} onOpenChange={(open) => !open && setViewing(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle className="truncate pe-8">{viewing?.name}</DialogTitle>
            <DialogDescription>{formatBytes(viewing?.size_bytes ?? null)}</DialogDescription>
          </DialogHeader>
          {viewing && previews[viewing.id] && (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element -- a signed, short-lived storage address */}
              <img
                src={previews[viewing.id]}
                alt={t("attach.preview", { name: viewing.name })}
                className="max-h-[70svh] w-full rounded-2xl bg-muted object-contain"
              />
              <div className="flex justify-end">
                <Button asChild variant="outline" size="sm">
                  <a href={previews[viewing.id]} target="_blank" rel="noopener noreferrer">
                    <ExternalLink />
                    {t("attach.openOriginal")}
                  </a>
                </Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
