/** Shared attachment constants and helpers, safe on both client and server. */

/** Matches the storage bucket limit and the DB check constraint. */
export const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

export const ATTACHMENT_BUCKET = "task-attachments";

/** How long a download link stays valid, in seconds. */
export const SIGNED_URL_TTL = 60 * 10;

export function formatBytes(bytes: number | null): string {
  if (bytes === null || bytes < 0) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Build the object key for an upload.
 *
 * The task id is the first path segment because the storage policy reads it to
 * decide whether the uploader may write here. The random prefix keeps two
 * people uploading "screenshot.png" from colliding.
 */
export function attachmentPath(taskId: string, fileName: string): string {
  // Stem and extension are sanitised apart, because `\w` is ASCII and this
  // company names things in Arabic. "عقد الإيجار.pdf" run through one pass
  // came out as "pdf": every letter stripped, then the leading dot with them,
  // so the object key carried no extension at all and the file downloaded as
  // a string of hex that nothing would open. The name people read is stored
  // on the row and is untouched by any of this; the key only has to be safe
  // and end in the right three letters.
  const dot = fileName.lastIndexOf(".");
  const hasExtension = dot > 0 && dot < fileName.length - 1;

  const ascii = (value: string) =>
    value
      .normalize("NFKD")
      .replace(/[^\w.\- ]+/g, "")
      .replace(/\s+/g, "-")
      .replace(/^[.-]+/, "");

  const stem =
    ascii(hasExtension ? fileName.slice(0, dot) : fileName).slice(-100) || "file";
  // Dots and dashes have no business inside an extension.
  const extension = hasExtension
    ? fileName.slice(dot + 1).normalize("NFKD").replace(/[^\w]+/g, "").slice(0, 16)
    : "";

  return `${taskId}/${crypto.randomUUID()}-${stem}${extension ? `.${extension}` : ""}`;
}

/** Hostname of a link attachment, for display. Falls back to the raw value. */
export function linkHost(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}
