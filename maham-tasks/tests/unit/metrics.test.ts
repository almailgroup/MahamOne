import { describe, expect, it } from "vitest";

import { summarise } from "@/lib/metrics";
import type { Profile, TaskWithAssignees } from "@/lib/supabase/database.types";

const hoursFromNow = (h: number) => new Date(Date.now() + h * 3600_000).toISOString();

const task = (
  status: string,
  dueAt: string | null,
  assignees: Profile[] = [],
): TaskWithAssignees =>
  ({ id: Math.random().toString(), status, priority: "medium", due_at: dueAt, assignees }) as unknown as TaskWithAssignees;

describe("summarise", () => {
  it("counts each status and derives pending from done", () => {
    const m = summarise([
      task("todo", null),
      task("todo", null),
      task("in_progress", null),
      task("in_review", null),
      task("done", null),
    ]);
    expect(m).toMatchObject({ total: 5, todo: 2, inProgress: 1, inReview: 1, done: 1, pending: 4 });
  });

  it("counts overdue only for work that is not done", () => {
    const m = summarise([task("todo", hoursFromNow(-1)), task("done", hoursFromNow(-99))]);
    expect(m.overdue).toBe(1);
  });

  it("does not count an undated task as overdue", () => {
    expect(summarise([task("todo", null)]).overdue).toBe(0);
  });

  it("reports 0% completion for an empty board rather than dividing by zero", () => {
    expect(summarise([]).completionRate).toBe(0);
  });

  it("rounds the completion rate", () => {
    expect(summarise([task("done", null), task("todo", null), task("todo", null)]).completionRate).toBe(33);
  });
});
