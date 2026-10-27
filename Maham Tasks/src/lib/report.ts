import { officeClock } from "@/lib/work-week";

/**
 * The Reports page's periods, and what the report hands back.
 *
 * Days are the office's: "the last four weeks" ends today in Kuwait, however
 * late it is in UTC. The report itself is public.work_report (migration 43).
 */

export const REPORT_PERIODS = ["4w", "12w", "year"] as const;
export type ReportPeriod = (typeof REPORT_PERIODS)[number];

export type ReportRange = {
  period: ReportPeriod;
  /** Inclusive ISO days, office time. */
  first: string;
  last: string;
  /** One bar per week, or per month for a year. */
  grain: "week" | "month";
};

export type ReportBucket = { starts: string; added: number; finished: number };
export type ReportPerson = { id: string; name: string; open: number; overdue: number };
export type ReportProject = { id: string; name: string; total: number; done: number; overdue: number };

export type WorkReport = {
  finished: number;
  finishedBefore: number;
  added: number;
  addedBefore: number;
  onTime: number;
  withDue: number;
  onTimeBefore: number;
  withDueBefore: number;
  overdueNow: number;
  buckets: ReportBucket[];
  people: ReportPerson[];
  projects: ReportProject[];
};

export function isReportPeriod(value: string | undefined): value is ReportPeriod {
  return REPORT_PERIODS.includes(value as ReportPeriod);
}

function daysBefore(day: string, days: number): string {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

export function reportRange(period: ReportPeriod, now: Date = new Date()): ReportRange {
  const today = officeClock(now).day;
  switch (period) {
    case "12w":
      return { period, first: daysBefore(today, 83), last: today, grain: "week" };
    case "year":
      return { period, first: `${today.slice(0, 4)}-01-01`, last: today, grain: "month" };
    case "4w":
    default:
      return { period: "4w", first: daysBefore(today, 27), last: today, grain: "week" };
  }
}

/** Finished on time, as a whole percentage — or null with nothing to judge. */
export function onTimeRate(onTime: number, withDue: number): number | null {
  return withDue === 0 ? null : Math.round((onTime / withDue) * 100);
}

/** The top of a value axis: the next clean number at or above the largest value. */
export function niceMax(value: number): number {
  if (value <= 4) return 4;
  const power = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 2, 2.5, 5, 10]) {
    if (step * power >= value) return step * power;
  }
  return 10 * power;
}
