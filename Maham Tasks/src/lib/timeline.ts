import { COMPANY_TIME_ZONE, FIRST_DAY_OF_WEEK, officeClock } from "@/lib/work-week";
import type { ProjectMilestone, TaskStatus } from "@/lib/supabase/database.types";

/**
 * Where everything on a project's timeline goes.
 *
 * Days are calendar days in the office, "2026-11-05", because a milestone is
 * a date rather than an instant and "is it late" is asked in Kuwait. The
 * chart draws from fractions of the range, so nothing here knows about
 * pixels or which way the page reads.
 */

export type TimelineTask = {
  id: string;
  title: string;
  status: TaskStatus;
  due_at: string | null;
  milestone_id?: string | null;
};

export type MilestoneState = "reached" | "late" | "due";

export type TimelinePoint<T extends TimelineTask = TimelineTask> = {
  task: T;
  day: string;
  /** Centre of its day, 0 at the range's start and 1 at its end. */
  at: number;
  overdue: boolean;
};

export type TimelineLane<T extends TimelineTask = TimelineTask> = {
  /** Null for the lane of dated work under no milestone. */
  milestone: ProjectMilestone | null;
  state: MilestoneState | null;
  /** Days from today to the milestone: negative once it has passed. */
  daysLeft: number | null;
  /** The stretch from its earliest task to its date, as fractions. */
  from: number;
  to: number;
  points: TimelinePoint<T>[];
};

export type TimelineTick = { day: string; at: number };

export type TimelineLayout<T extends TimelineTask = TimelineTask> = {
  first: string;
  last: string;
  /** How many days the range covers, both ends included. */
  days: number;
  grain: "week" | "month";
  ticks: TimelineTick[];
  today: number;
  lanes: TimelineLane<T>[];
};

const DAY_MS = 86_400_000;

/** Days since 1970-01-01 for a "YYYY-MM-DD" day. */
export function dayNumber(day: string): number {
  return Math.round(Date.parse(`${day}T00:00:00Z`) / DAY_MS);
}

function dayFromNumber(n: number): string {
  return new Date(n * DAY_MS).toISOString().slice(0, 10);
}

/** The office's calendar day for an instant. */
export function officeDay(iso: string | Date, timeZone: string = COMPANY_TIME_ZONE): string {
  return officeClock(typeof iso === "string" ? new Date(iso) : iso, timeZone).day;
}

/** Where a milestone stands today, and how many days away it is. */
export function milestoneState(
  milestone: Pick<ProjectMilestone, "due_on" | "done_at">,
  today: string,
): { state: MilestoneState; daysLeft: number } {
  const daysLeft = dayNumber(milestone.due_on) - dayNumber(today);
  if (milestone.done_at) return { state: "reached", daysLeft };
  return { state: daysLeft < 0 ? "late" : "due", daysLeft };
}

/** Milestones in the order they fall due; the same day, by name. */
export function sortMilestones<M extends Pick<ProjectMilestone, "due_on" | "title">>(milestones: M[]): M[] {
  return [...milestones].sort(
    (a, b) => a.due_on.localeCompare(b.due_on) || a.title.localeCompare(b.title),
  );
}

/** Up to sixteen weeks reads week by week; anything longer, month by month. */
const WEEKLY_UP_TO_DAYS = 16 * 7;

/**
 * Lay out a project's milestones and the dated tasks under them.
 *
 * The range runs from the week of the earliest thing on it (today included,
 * so "now" is always on the chart) to the end of the week of the latest,
 * and at least a fortnight past today so a project with nothing ahead still
 * shows where it would go. Done work outside every milestone is history,
 * not plan, and is left off.
 */
export function layoutTimeline<T extends TimelineTask>(
  milestones: ProjectMilestone[],
  tasks: T[],
  now: Date = new Date(),
): TimelineLayout<T> {
  const today = officeDay(now);
  const known = new Set(milestones.map((milestone) => milestone.id));
  const dated = tasks
    .filter((task) => task.due_at)
    .map((task) => ({ task, day: officeDay(task.due_at as string) }));

  const days = [
    dayNumber(today),
    dayNumber(today) + 13,
    ...milestones.map((milestone) => dayNumber(milestone.due_on)),
    ...dated
      .filter(({ task }) => (task.milestone_id && known.has(task.milestone_id)) || task.status !== "done")
      .map(({ day }) => dayNumber(day)),
  ];

  // Sunday on or before the earliest, Saturday on or after the latest.
  const lowest = Math.min(...days);
  const highest = Math.max(...days);
  const weekday = (n: number) => new Date(n * DAY_MS).getUTCDay();
  const start = lowest - ((weekday(lowest) - FIRST_DAY_OF_WEEK + 7) % 7);
  const end = highest + ((FIRST_DAY_OF_WEEK + 6 - weekday(highest) + 7) % 7);
  const span = end - start + 1;
  const at = (day: string) => (dayNumber(day) - start + 0.5) / span;

  const grain = span <= WEEKLY_UP_TO_DAYS ? "week" : "month";
  const ticks: TimelineTick[] = [];
  for (let n = start; n <= end; n++) {
    const day = dayFromNumber(n);
    if (grain === "week" ? weekday(n) === FIRST_DAY_OF_WEEK : day.endsWith("-01")) {
      ticks.push({ day, at: (n - start) / span });
    }
  }

  const point = ({ task, day }: { task: T; day: string }): TimelinePoint<T> => ({
    task,
    day,
    at: at(day),
    overdue: task.status !== "done" && new Date(task.due_at as string) < now,
  });
  const byDay = (a: TimelinePoint<T>, b: TimelinePoint<T>) => a.at - b.at;

  const lanes: TimelineLane<T>[] = sortMilestones(milestones).map((milestone) => {
    const points = dated.filter(({ task }) => task.milestone_id === milestone.id).map(point).sort(byDay);
    const to = at(milestone.due_on);
    const { state, daysLeft } = milestoneState(milestone, today);
    return {
      milestone,
      state,
      daysLeft,
      from: Math.min(to, ...points.map((p) => p.at)),
      to,
      points,
    };
  });

  const loose = dated
    .filter(({ task }) => !(task.milestone_id && known.has(task.milestone_id)) && task.status !== "done")
    .map(point)
    .sort(byDay);
  if (loose.length > 0) {
    lanes.push({
      milestone: null,
      state: null,
      daysLeft: null,
      from: loose[0].at,
      to: loose[loose.length - 1].at,
      points: loose,
    });
  }

  return {
    first: dayFromNumber(start),
    last: dayFromNumber(end),
    days: span,
    grain,
    ticks,
    today: at(today),
    lanes,
  };
}

/** How much of a milestone's work is done, from every task under it. */
export function milestoneProgress(
  milestoneId: string,
  tasks: Pick<TimelineTask, "status" | "milestone_id">[],
): { done: number; total: number } {
  const under = tasks.filter((task) => task.milestone_id === milestoneId);
  return { done: under.filter((task) => task.status === "done").length, total: under.length };
}
