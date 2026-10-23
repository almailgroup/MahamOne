import { describe, expect, it } from "vitest";

import { followUpSchema, taskSchema } from "@/lib/validation";

const base = { title: "Ship it", status: "todo", priority: "medium", assigneeIds: [] };

describe("taskSchema.dueAt", () => {
  /**
   * The server must only ever accept an absolute instant. Accepting the raw
   * "2026-09-15T17:30" an input produces is what let the timezone bug happen
   * silently; rejecting it means the mistake cannot come back unnoticed.
   */
  it("rejects a wall-clock string with no offset", () => {
    const result = taskSchema.safeParse({ ...base, dueAt: "2026-09-15T17:30" });
    expect(result.success).toBe(false);
  });

  it("accepts an absolute instant", () => {
    const result = taskSchema.safeParse({ ...base, dueAt: "2026-09-15T13:30:00.000Z" });
    expect(result.success).toBe(true);
  });

  it("accepts an empty string as 'no due date'", () => {
    const result = taskSchema.safeParse({ ...base, dueAt: "" });
    expect(result.success).toBe(true);
  });
});

describe("followUpSchema", () => {
  it("rejects wall-clock and accepts an instant, like dueAt", () => {
    expect(followUpSchema.safeParse({ followUpAt: "2026-09-15T09:00" }).success).toBe(false);
    expect(followUpSchema.safeParse({ followUpAt: "2026-09-15T05:00:00.000Z" }).success).toBe(true);
  });
});

describe("taskSchema", () => {
  it("requires a title and trims it", () => {
    expect(taskSchema.safeParse({ ...base, title: "   " }).success).toBe(false);
    const ok = taskSchema.safeParse({ ...base, title: "  Ship it  " });
    expect(ok.success && ok.data.title).toBe("Ship it");
  });

  it("refuses an unknown status or priority", () => {
    expect(taskSchema.safeParse({ ...base, status: "archived" }).success).toBe(false);
    expect(taskSchema.safeParse({ ...base, priority: "critical" }).success).toBe(false);
  });

  it("refuses assignee ids that are not uuids", () => {
    expect(taskSchema.safeParse({ ...base, assigneeIds: ["nope"] }).success).toBe(false);
  });
});
