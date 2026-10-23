import { describe, expect, it } from "vitest";

import { csvCell, csvFilename, tasksToCsv } from "@/lib/csv";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

describe("csvCell", () => {
  it("leaves plain values alone", () => {
    expect(csvCell("Book the van")).toBe("Book the van");
    expect(csvCell(3)).toBe("3");
    expect(csvCell(null)).toBe("");
  });

  /** The three characters that break a spreadsheet if they are not quoted. */
  it("quotes commas, quotes and newlines, doubling the quotes", () => {
    expect(csvCell("van, keys")).toBe('"van, keys"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell("line one\nline two")).toBe('"line one\nline two"');
  });
});

describe("tasksToCsv", () => {
  const rows = [
    {
      title: "Chase the customs paperwork, urgently",
      description: null,
      status: "in_progress",
      priority: "urgent",
      project_id: "p1",
      due_at: "2026-09-14T16:00:00Z",
      created_at: "2026-09-10T09:00:00Z",
      assignees: [{ full_name: "Sara Khan", email: "s@x" }, { full_name: null, email: "k@x" }],
    },
  ] as unknown as TaskWithAssignees[];

  it("writes a header, the labels people see, and CRLF lines", () => {
    const csv = tasksToCsv(rows, () => "Freight");
    const [header, row, trailing] = csv.split("\r\n");
    // The byte-order mark tells Excel the file is UTF-8, so Arabic survives.
    expect(header).toBe("\uFEFFTitle,Project,Status,Priority,Due,Assignees,Created,Description");
    expect(row).toBe(
      '"Chase the customs paperwork, urgently",Freight,In Progress,Urgent,2026-09-14T16:00:00Z,Sara Khan; k@x,2026-09-10T09:00:00Z,',
    );
    expect(trailing).toBe("");
  });

  it("omits the project column where there is no project to name", () => {
    expect(tasksToCsv(rows).split("\r\n")[0]).not.toContain("Project");
  });
});

describe("csvFilename", () => {
  it("is safe to save and says what and when", () => {
    expect(csvFilename("Freight operations")).toMatch(/^freight-operations-\d{4}-\d{2}-\d{2}\.csv$/);
    expect(csvFilename("  ")).toMatch(/^tasks-\d{4}-\d{2}-\d{2}\.csv$/);
  });
});
