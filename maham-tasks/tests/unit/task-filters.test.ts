import { describe, expect, it } from "vitest";

import { TASK_FILTERS, applyTaskFilter, isTaskFilter, nextSort } from "@/lib/task-filters";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

const hours = (h: number) => new Date(Date.now() + h * 3600_000).toISOString();
const task = (over: Partial<TaskWithAssignees>): TaskWithAssignees =>
  ({ id: Math.random().toString(), status: "todo", priority: "medium",
     due_at: null, assignees: [], ...over }) as unknown as TaskWithAssignees;

const set = [
  task({ status: "todo", due_at: hours(-2) }),   // overdue
  task({ status: "todo", due_at: hours(1) }),
  task({ status: "in_progress" }),
  task({ status: "in_review" }),
  task({ status: "done", due_at: hours(-50) }),  // late, but finished
];

describe("applyTaskFilter", () => {
  it("returns everything under 'all'", () => {
    expect(applyTaskFilter(set, "all").length).toBe(5);
  });

  it("treats pending as everything not done", () => {
    expect(applyTaskFilter(set, "pending").length).toBe(4);
  });

  it("never calls a finished task overdue", () => {
    const overdue = applyTaskFilter(set, "overdue");
    expect(overdue.every((t) => t.status !== "done")).toBe(true);
    expect(overdue.length).toBe(1);
  });

  it("matches single statuses", () => {
    expect(applyTaskFilter(set, "todo").length).toBe(2);
    expect(applyTaskFilter(set, "in_review").length).toBe(1);
    expect(applyTaskFilter(set, "done").length).toBe(1);
  });

  it("excludes finished work from due_today", () => {
    expect(applyTaskFilter(set, "due_today").every((t) => t.status !== "done")).toBe(true);
  });

  /**
   * The dashboard tiles and this function share one vocabulary. If a filter is
   * ever added to the list without a branch here it would silently fall
   * through to "everything", which is the wrong answer dressed up as a right
   * one — every filter except `all` must narrow something.
   */
  it("has a real branch for every filter it advertises", () => {
    for (const { value } of TASK_FILTERS) {
      if (value === "all" || value === "pending") continue;
      expect(applyTaskFilter(set, value).length).toBeLessThan(set.length);
    }
  });
});

describe("isTaskFilter", () => {
  it("accepts known values and rejects anything else", () => {
    expect(isTaskFilter("overdue")).toBe(true);
    expect(isTaskFilter("archived")).toBe(false);
    expect(isTaskFilter(undefined)).toBe(false);
  });
});

describe("nextSort", () => {
  it("sorts by a new column, then flips it, then goes back to the board's order", () => {
    const asc = nextSort(null, "due");
    expect(asc).toEqual({ key: "due", direction: "asc" });
    const desc = nextSort(asc, "due");
    expect(desc).toEqual({ key: "due", direction: "desc" });
    expect(nextSort(desc, "due")).toBeNull();
  });

  it("starts a different column from the top, whatever the last one was doing", () => {
    expect(nextSort({ key: "due", direction: "desc" }, "priority")).toEqual({
      key: "priority",
      direction: "asc",
    });
  });
});
