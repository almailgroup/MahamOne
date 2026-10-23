import { describe, expect, it } from "vitest";

import { needsAttention, STALE_AFTER_DAYS } from "@/lib/project-health";
import type { ProjectHealthRow } from "@/lib/supabase/database.types";

const NOW = Date.parse("2026-10-02T09:00:00Z");
const daysAgo = (n: number) => new Date(NOW - n * 86_400_000).toISOString();

const row = (over: Partial<ProjectHealthRow>): ProjectHealthRow => ({
  project_id: over.name ?? "p",
  name: "Project",
  latest_status: "on_track",
  latest_body: "Fine.",
  latest_at: daysAgo(1),
  latest_author: "Sara Khan",
  open_tasks: 3,
  overdue_tasks: 0,
  ...over,
});

const names = (rows: ProjectHealthRow[]) =>
  needsAttention(rows, NOW).map((item) => item.name);

describe("needsAttention", () => {
  it("leaves out a project that is on track, current and on time", () => {
    expect(needsAttention([row({ name: "Fine" })], NOW)).toEqual([]);
  });

  it("lists a project its owner calls off track or at risk", () => {
    expect(
      names([
        row({ name: "Off", latest_status: "off_track" }),
        row({ name: "Risk", latest_status: "at_risk" }),
      ]),
    ).toEqual(["Off", "Risk"]);
  });

  it("lists late work even when the owner says it is on track", () => {
    // The honest case: the update is reassuring and the board is not.
    const [item] = needsAttention([row({ name: "Late", overdue_tasks: 2 })], NOW);
    expect(item.reasons).toEqual([{ kind: "overdue", count: 2 }]);
  });

  it("lists a project with open work and no word on it in two weeks", () => {
    const [item] = needsAttention(
      [row({ name: "Quiet", latest_at: daysAgo(STALE_AFTER_DAYS + 1) })],
      NOW,
    );
    expect(item.reasons[0].kind).toBe("silent");
  });

  it("and one that has never had an update at all", () => {
    const [item] = needsAttention(
      [row({ name: "New", latest_status: null, latest_at: null, latest_body: null })],
      NOW,
    );
    expect(item.reasons).toEqual([{ kind: "silent", since: null }]);
  });

  it("does not nag about a quiet project with nothing open", () => {
    expect(
      names([row({ name: "Done", open_tasks: 0, latest_at: null, latest_status: null })]),
    ).toEqual([]);
  });

  it("gives every reason that applies, once per project", () => {
    const [item] = needsAttention(
      [
        row({
          name: "All of it",
          latest_status: "at_risk",
          latest_at: daysAgo(30),
          overdue_tasks: 4,
        }),
      ],
      NOW,
    );
    expect(item.reasons.map((reason) => reason.kind)).toEqual([
      "status",
      "overdue",
      "silent",
    ]);
  });

  it("puts the worst first: off track, at risk, late, then quiet", () => {
    expect(
      names([
        row({ name: "Quiet", latest_at: daysAgo(20) }),
        row({ name: "Late", overdue_tasks: 1 }),
        row({ name: "Risk", latest_status: "at_risk" }),
        row({ name: "Off", latest_status: "off_track" }),
      ]),
    ).toEqual(["Off", "Risk", "Late", "Quiet"]);
  });

  it("reads counts that arrive as strings", () => {
    // PostgREST sends bigint as a number today; nothing here depends on that.
    const [item] = needsAttention(
      [row({ overdue_tasks: "3" as unknown as number })],
      NOW,
    );
    expect(item.overdueTasks).toBe(3);
  });
});
