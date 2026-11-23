import { describe, expect, it } from "vitest";

import { attachmentPath, formatBytes, linkHost } from "@/lib/attachments";
import { fileAttachmentSchema, linkAttachmentSchema } from "@/lib/validation";

/**
 * Real uploads are not exercised here — they go straight from the browser to
 * Supabase Storage and need a live bucket. What these pin down is the part
 * that decides *where* a file lands and *what* is allowed to be recorded,
 * which is the half that has security consequences.
 */
describe("attachmentPath", () => {
  it("puts the task id first, because the storage policy reads it", () => {
    const path = attachmentPath("task-123", "photo.png");
    expect(path.startsWith("task-123/")).toBe(true);
  });

  it("cannot be talked into climbing out of the task's folder", () => {
    const path = attachmentPath("task-123", "../../../etc/passwd");
    expect(path.startsWith("task-123/")).toBe(true);
    expect(path).not.toContain("..");
    expect(path).not.toContain("/etc/");
  });

  it("strips characters that have meaning in a path or a URL", () => {
    const name = attachmentPath("t", 'a"b?c#d%e&f.png').split("/")[1];
    expect(name).not.toMatch(/["?#%&]/);
  });

  it("keeps two identical filenames apart", () => {
    expect(attachmentPath("t", "screenshot.png")).not.toBe(
      attachmentPath("t", "screenshot.png"),
    );
  });

  it("still produces a usable name when everything is stripped", () => {
    const path = attachmentPath("t", "???");
    expect(path.split("/")[1]).toMatch(/file$/);
  });

  /**
   * The company names its documents in Arabic, and `\w` is ASCII.
   *
   * One sanitising pass over the whole filename removed every letter and then
   * the leading dot with them, so "عقد الإيجار.pdf" became "pdf": a key with
   * no extension, and a download nothing on the phone would open.
   */
  it("keeps the extension when the name itself is not ASCII", () => {
    const name = attachmentPath("t", "عقد الإيجار.pdf").split("/")[1];
    expect(name.endsWith(".pdf")).toBe(true);
  });

  it("keeps the extension on an English name too", () => {
    expect(attachmentPath("t", "August freight.xlsx").split("/")[1]).toMatch(
      /-August-freight\.xlsx$/,
    );
  });

  it("does not invent an extension where there was none", () => {
    expect(attachmentPath("t", "README").split("/")[1]).not.toContain(".");
  });

  it("takes the last extension, and leaves a double one alone", () => {
    expect(attachmentPath("t", "invoice.tar.gz").split("/")[1]).toMatch(
      /-invoice\.tar\.gz$/,
    );
  });

  it("keeps a dotfile inside the task folder", () => {
    const path = attachmentPath("t", ".env");
    expect(path.startsWith("t/")).toBe(true);
    expect(path.split("/")[1]).not.toMatch(/^[.-]/);
  });
});

describe("linkAttachmentSchema", () => {
  it("accepts http and https", () => {
    expect(linkAttachmentSchema.safeParse({ name: "Docs", url: "https://a.test/x" }).success).toBe(true);
    expect(linkAttachmentSchema.safeParse({ name: "Docs", url: "http://a.test/x" }).success).toBe(true);
  });

  it("refuses a javascript: URL", () => {
    // This one is the whole reason the check exists: the stored value is later
    // rendered as a link for other people to click.
    expect(
      linkAttachmentSchema.safeParse({ name: "x", url: "javascript:alert(1)" }).success,
    ).toBe(false);
  });

  it("refuses other schemes and an empty URL", () => {
    for (const url of ["data:text/html,<script>", "file:///etc/passwd", "ftp://a.test", ""]) {
      expect(linkAttachmentSchema.safeParse({ name: "x", url }).success, url).toBe(false);
    }
  });
});

describe("fileAttachmentSchema", () => {
  it("refuses a file larger than the bucket allows", () => {
    expect(fileAttachmentSchema.safeParse({
      name: "big.zip", storagePath: "t/big.zip", sizeBytes: 26_214_401,
    }).success).toBe(false);
  });

  it("refuses a negative size", () => {
    expect(fileAttachmentSchema.safeParse({
      name: "x", storagePath: "t/x", sizeBytes: -1,
    }).success).toBe(false);
  });
});

describe("linkHost", () => {
  it("shows the bare host, and falls back to the raw value", () => {
    expect(linkHost("https://www.example.com/a/b")).toBe("example.com");
    expect(linkHost("not a url")).toBe("not a url");
  });
});

describe("formatBytes", () => {
  it("scales and handles nothing", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2 KB");
    expect(formatBytes(5 * 1024 * 1024)).toBe("5.0 MB");
    expect(formatBytes(null)).toBe("");
  });
});
