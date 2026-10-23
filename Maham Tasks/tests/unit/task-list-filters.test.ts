import { describe, expect, it } from "vitest";
// ---------------------------------------------------------------------------
// The shared filter bar and list sorting
// ---------------------------------------------------------------------------

import {
  EMPTY_FILTERS,
  filtersActive,
  matchesFilters,
  readFiltersFromParams,
  sortTasks,
  writeFiltersToParams,
} from "@/lib/task-filters";
import type { Profile, TaskWithAssignees } from "@/lib/supabase/database.types";

const person = (id: string): Profile =>
  ({ id, email: `${id}@x`, full_name: id, role: "member" }) as unknown as Profile;

const task = (over: Partial<TaskWithAssignees>): TaskWithAssignees =>
  ({
    id: over.title ?? "t",
    title: "Task",
    description: null,
    status: "todo",
    priority: "medium",
    project_id: null,
    due_at: null,
    assignees: [],
    labelIds: [],
    ...over,
  }) as TaskWithAssignees;

describe("matchesFilters", () => {
  const sara = person("sara");
  const rows = [
    task({ title: "Book the van", status: "todo", priority: "high", assignees: [sara], labelIds: ["bank"] }),
    task({ title: "Print manifest", status: "done", priority: "low", description: "for customs" }),
  ];

  it("matches everything with no filters", () => {
    expect(rows.filter((t) => matchesFilters(t, EMPTY_FILTERS))).toHaveLength(2);
  });

  it("searches the description as well as the title", () => {
    const hits = rows.filter((t) => matchesFilters(t, { ...EMPTY_FILTERS, query: "customs" }));
    expect(hits.map((t) => t.title)).toEqual(["Print manifest"]);
  });

  it("understands unassigned as a person", () => {
    const hits = rows.filter((t) => matchesFilters(t, { ...EMPTY_FILTERS, assignee: "unassigned" }));
    expect(hits.map((t) => t.title)).toEqual(["Print manifest"]);
    const hers = rows.filter((t) => matchesFilters(t, { ...EMPTY_FILTERS, assignee: "sara" }));
    expect(hers.map((t) => t.title)).toEqual(["Book the van"]);
  });

  it("narrows to a label", () => {
    const hits = rows.filter((t) => matchesFilters(t, { ...EMPTY_FILTERS, label: "bank" }));
    expect(hits.map((t) => t.title)).toEqual(["Book the van"]);
    expect(filtersActive({ ...EMPTY_FILTERS, label: "bank" })).toBe(true);
  });

  it("knows when nothing is applied", () => {
    expect(filtersActive(EMPTY_FILTERS)).toBe(false);
    expect(filtersActive({ ...EMPTY_FILTERS, query: "  " })).toBe(false);
    expect(filtersActive({ ...EMPTY_FILTERS, status: "done" })).toBe(true);
  });
});

describe("filters in the URL", () => {
  it("round-trips, and leaves defaults out of the address", () => {
    const filters = {
      query: "van",
      status: "todo" as const,
      priority: "all" as const,
      assignee: "sara",
      label: "bank",
    };
    const params = writeFiltersToParams(filters, new URLSearchParams("new=1"));
    expect(params.toString()).toBe("new=1&q=van&status=todo&assignee=sara&label=bank");
    expect(readFiltersFromParams(params)).toEqual(filters);
  });

  it("drops a value that is not a real status or priority", () => {
    const read = readFiltersFromParams(new URLSearchParams("status=bogus&priority=urgent"));
    expect(read.status).toBe("all");
    expect(read.priority).toBe("urgent");
  });

  it("clearing a filter removes its parameter rather than writing all", () => {
    const params = writeFiltersToParams(EMPTY_FILTERS, new URLSearchParams("q=van&status=todo"));
    expect(params.toString()).toBe("");
  });
});

describe("sortTasks", () => {
  const rows = [
    task({ title: "b", priority: "low", due_at: "2026-09-20T10:00:00Z", status: "done" }),
    task({ title: "a", priority: "urgent", due_at: null, status: "todo" }),
    task({ title: "c", priority: "high", due_at: "2026-09-10T10:00:00Z", status: "in_review" }),
  ];

  it("leaves the order alone with no sort, which is the board's own order", () => {
    expect(sortTasks(rows, null)).toBe(rows);
  });

  it("sorts by priority weight, not alphabetically", () => {
    expect(sortTasks(rows, { key: "priority", direction: "desc" }).map((t) => t.priority)).toEqual([
      "urgent",
      "high",
      "low",
    ]);
  });

  it("keeps undated tasks at the bottom whichever way the dates go", () => {
    expect(sortTasks(rows, { key: "due", direction: "asc" }).map((t) => t.title)).toEqual(["c", "b", "a"]);
    expect(sortTasks(rows, { key: "due", direction: "desc" }).map((t) => t.title)).toEqual(["b", "c", "a"]);
  });

  it("sorts status in workflow order", () => {
    expect(sortTasks(rows, { key: "status", direction: "asc" }).map((t) => t.status)).toEqual([
      "todo",
      "in_review",
      "done",
    ]);
  });
});
