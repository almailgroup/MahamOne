import type { ProjectHealthRow, ProjectStatus } from "@/lib/supabase/database.types";

/**
 * Which projects somebody should look at, and why.
 *
 * The database reports every live project's latest status and how much of
 * its work is open and late; this decides which of them are worth a
 * director's attention. It lives here rather than in SQL so the rule can be
 * read in one place and tested without a database.
 *
 * Four reasons, and a project is listed once with every one that applies:
 *
 *   off track   its owner says so
 *   at risk     its owner says so
 *   overdue     it has late work — even when the owner says "on track",
 *               which is exactly the case worth seeing
 *   silent      it has open work and nobody has said how it is going in two
 *               weeks, or ever
 *
 * Everything else is left out. A list of every project with a green tick
 * beside most of them is a list nobody reads; an empty one means there is
 * nothing to do.
 */

/** How long a project with open work may go without an update. */
export const STALE_AFTER_DAYS = 14;

const DAY_MS = 86_400_000;

export type AttentionReason =
  | { kind: "status"; status: Exclude<ProjectStatus, "on_track"> }
  | { kind: "overdue"; count: number }
  | { kind: "silent"; since: string | null };

export type AttentionItem = {
  projectId: string;
  name: string;
  reasons: AttentionReason[];
  latestStatus: ProjectStatus | null;
  latestBody: string | null;
  latestAt: string | null;
  latestAuthor: string | null;
  openTasks: number;
  overdueTasks: number;
};

/** Worst first. A project its owner calls off track outranks a quiet one. */
function severity(item: AttentionItem): number {
  if (item.latestStatus === "off_track") return 3;
  if (item.latestStatus === "at_risk") return 2;
  if (item.overdueTasks > 0) return 1;
  return 0;
}

export function needsAttention(
  rows: ProjectHealthRow[],
  nowMs: number,
  staleDays = STALE_AFTER_DAYS,
): AttentionItem[] {
  const items: AttentionItem[] = [];

  for (const row of rows) {
    // bigint arrives as a number from PostgREST, but say so rather than trust it.
    const openTasks = Number(row.open_tasks ?? 0);
    const overdueTasks = Number(row.overdue_tasks ?? 0);
    const reasons: AttentionReason[] = [];

    if (row.latest_status === "off_track" || row.latest_status === "at_risk") {
      reasons.push({ kind: "status", status: row.latest_status });
    }

    if (overdueTasks > 0) {
      reasons.push({ kind: "overdue", count: overdueTasks });
    }

    // A project with nothing open has nothing to report, however long it has
    // been quiet. One with work in flight and no word on it does.
    const quiet =
      row.latest_at === null ||
      nowMs - new Date(row.latest_at).getTime() > staleDays * DAY_MS;
    if (openTasks > 0 && quiet) {
      reasons.push({ kind: "silent", since: row.latest_at });
    }

    if (reasons.length === 0) continue;

    items.push({
      projectId: row.project_id,
      name: row.name,
      reasons,
      latestStatus: row.latest_status,
      latestBody: row.latest_body,
      latestAt: row.latest_at,
      latestAuthor: row.latest_author,
      openTasks,
      overdueTasks,
    });
  }

  return items.sort(
    (a, b) =>
      severity(b) - severity(a) ||
      b.overdueTasks - a.overdueTasks ||
      a.name.localeCompare(b.name),
  );
}
