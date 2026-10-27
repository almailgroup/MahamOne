import { describe, expect, it } from "vitest";

import { mergeTaskUpdate } from "@/lib/realtime/use-task-stream";
import type { Task, TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * Realtime hands over the `tasks` row and nothing else.
 *
 * Everything a list shows beside the row itself — the faces, the step count —
 * is joined on by the server query, so the merge has to carry it across. It
 * is not a nicety: ChecklistProgressBadge reads `progress.total`, and a task
 * whose checklist went missing throws on the next render of the board.
 */
const onScreen: TaskWithAssignees = {
  id: "t1",
  project_id: "p1",
  title: "Collect the bank letters",
  description: null,
  status: "todo",
  priority: "medium",
  due_at: null,
  follow_up_at: null,
  follow_up_note: null,
  repeat_every: null,
  repeat_interval: 1,
  position: 1024,
  created_by: "u1",
  created_at: "2026-09-01T00:00:00.000Z",
  updated_at: "2026-09-01T00:00:00.000Z",
  deleted_at: null,
  assignees: [
    {
      id: "u2",
      email: "sara@almailgroup.com",
      full_name: "Sara",
      avatar_url: null,
      job_title: null,
      role: "member",
      created_at: "2026-09-01T00:00:00.000Z",
      updated_at: "2026-09-01T00:00:00.000Z",
    },
  ],
  checklist: { done: 1, total: 3 },
} as unknown as TaskWithAssignees;

/** What Postgres broadcasts: columns only. */
const broadcast = {
  ...(Object.fromEntries(
    Object.entries(onScreen).filter(
      ([key]) => key !== "assignees" && key !== "checklist",
    ),
  ) as unknown as Task),
  status: "in_progress",
  updated_at: "2026-09-02T00:00:00.000Z",
} as Task;

describe("mergeTaskUpdate", () => {
  it("takes the columns from the row that arrived", () => {
    const merged = mergeTaskUpdate(onScreen, broadcast);
    expect(merged.status).toBe("in_progress");
    expect(merged.updated_at).toBe("2026-09-02T00:00:00.000Z");
  });

  it("keeps the assignees, which the broadcast does not carry", () => {
    expect(mergeTaskUpdate(onScreen, broadcast).assignees).toEqual(
      onScreen.assignees,
    );
  });

  it("keeps the checklist counts, which it does not carry either", () => {
    // Without this the badge is handed `undefined` and reading `.total`
    // throws, taking the whole board to the error boundary.
    expect(mergeTaskUpdate(onScreen, broadcast).checklist).toEqual({
      done: 1,
      total: 3,
    });
  });
});
