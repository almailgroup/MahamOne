import { describe, expect, it } from "vitest";

import {
  dayNumber,
  layoutTimeline,
  milestoneProgress,
  milestoneState,
  officeDay,
  sortMilestones,
  type TimelineTask,
} from "@/lib/timeline";
import type { ProjectMilestone } from "@/lib/supabase/database.types";

/** Wednesday 14 October 2026, mid-morning in Kuwait. */
const NOW = new Date("2026-10-14T07:00:00Z");

const milestone = (id: string, due_on: string, done_at: string | null = null): ProjectMilestone => ({
  id,
  project_id: "p",
  title: id,
  due_on,
  done_at,
  created_by: null,
  created_at: "2026-10-01T00:00:00Z",
  updated_at: "2026-10-01T00:00:00Z",
});

const task = (
  id: string,
  due_at: string | null,
  milestone_id: string | null = null,
  status: TimelineTask["status"] = "todo",
): TimelineTask => ({ id, title: id, status, due_at, milestone_id });

describe("a milestone's state", () => {
  it("is late once its day has passed in Kuwait, and reached once marked", () => {
    expect(milestoneState(milestone("a", "2026-10-13"), "2026-10-14")).toEqual({ state: "late", daysLeft: -1 });
    expect(milestoneState(milestone("a", "2026-10-14"), "2026-10-14")).toEqual({ state: "due", daysLeft: 0 });
    expect(milestoneState(milestone("a", "2026-10-13", "2026-10-12T09:00:00Z"), "2026-10-14").state).toBe(
      "reached",
    );
  });

  it("counts the office's day, not UTC's", () => {
    // 22:30 UTC on the 14th is 01:30 on the 15th in Kuwait.
    expect(officeDay("2026-10-14T22:30:00Z")).toBe("2026-10-15");
  });
});

describe("the timeline's range", () => {
  it("runs Sunday to Saturday, from today to at least a fortnight on", () => {
    const layout = layoutTimeline([], [], NOW);
    expect(layout.first).toBe("2026-10-11");
    expect(layout.last).toBe("2026-10-31");
    expect(layout.days).toBe(21);
    expect(layout.grain).toBe("week");
    expect(layout.ticks.map((tick) => tick.day)).toEqual(["2026-10-11", "2026-10-18", "2026-10-25"]);
    // Wednesday is the fourth day of the first of three weeks.
    expect(layout.today).toBeCloseTo(3.5 / 21);
  });

  it("reaches back to late work and on to the last milestone", () => {
    const layout = layoutTimeline(
      [milestone("move", "2026-12-03")],
      [task("late", "2026-09-30T09:00:00Z")],
      NOW,
    );
    expect(layout.first).toBe("2026-09-27");
    expect(layout.last).toBe("2026-12-05");
  });

  it("goes month by month past sixteen weeks", () => {
    const layout = layoutTimeline([milestone("far", "2027-04-01")], [], NOW);
    expect(layout.grain).toBe("month");
    expect(layout.ticks[0].day).toBe("2026-11-01");
    expect(layout.ticks.every((tick) => tick.day.endsWith("-01"))).toBe(true);
  });
});

describe("the timeline's lanes", () => {
  const milestones = [milestone("move", "2026-12-03"), milestone("lease", "2026-11-05")];
  const tasks = [
    task("sign", "2026-11-02T09:00:00Z", "lease"),
    task("view", "2026-10-20T09:00:00Z", "lease", "done"),
    task("pack", "2026-12-01T09:00:00Z", "move"),
    task("chase", "2026-10-12T09:00:00Z"),
    task("old", "2026-09-01T09:00:00Z", null, "done"),
    task("undated", null, "move"),
  ];
  const layout = layoutTimeline(milestones, tasks, NOW);

  it("come in the order the milestones fall due, then the loose work", () => {
    expect(layout.lanes.map((lane) => lane.milestone?.id ?? "loose")).toEqual(["lease", "move", "loose"]);
  });

  it("stretch from their earliest task to their date", () => {
    const lease = layout.lanes[0];
    expect(lease.points.map((p) => p.task.id)).toEqual(["view", "sign"]);
    expect(lease.from).toBe(lease.points[0].at);
    expect(lease.to).toBeCloseTo((dayNumber("2026-11-05") - dayNumber(layout.first) + 0.5) / layout.days);
  });

  it("leave finished loose work off, and mark open work past its time", () => {
    const loose = layout.lanes[2];
    expect(loose.points.map((p) => p.task.id)).toEqual(["chase"]);
    expect(loose.points[0].overdue).toBe(true);
    expect(layout.lanes[0].points.find((p) => p.task.id === "view")?.overdue).toBe(false);
  });

  it("count progress from every task under the milestone, dated or not", () => {
    expect(milestoneProgress("move", tasks)).toEqual({ done: 0, total: 2 });
    expect(milestoneProgress("lease", tasks)).toEqual({ done: 1, total: 2 });
  });

  it("put a task under a milestone that is gone with the loose work", () => {
    const orphan = layoutTimeline([], [task("lost", "2026-10-20T09:00:00Z", "deleted")], NOW);
    expect(orphan.lanes).toHaveLength(1);
    expect(orphan.lanes[0].milestone).toBeNull();
  });

  it("sort the same day by name", () => {
    expect(
      sortMilestones([milestone("b", "2026-11-01"), milestone("a", "2026-11-01")]).map((m) => m.id),
    ).toEqual(["a", "b"]);
  });
});
