import type { Metadata } from "next";

import { CalendarView } from "@/components/tasks/calendar-view";
import {
  monthParam,
  monthWindow,
  parseMonthParam,
  startOfMonth,
  todayIn,
} from "@/lib/calendar";
import {
  countUndatedTasks,
  getProjects,
  getTasksDueBetween,
  getTeam,
  requireProfile,
} from "@/lib/data/queries";
import { getI18n, getTimeZone } from "@/lib/i18n/server";

type PageProps = { searchParams: Promise<{ month?: string }> };

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return { title: t("nav.calendar") };
}

/**
 * A month of due dates.
 *
 * Only that month is fetched. It used to ask for every task the viewer could
 * see and place them in the browser, which works until there are more tasks
 * than one response carries — and then the page quietly shows a slice of
 * them, chosen by when they were created rather than when they are due, with
 * nothing to say so.
 *
 * Placement is still the browser's job, because only the browser knows which
 * local day an instant falls on.
 */
export default async function CalendarPage({ searchParams }: PageProps) {
  const { month: raw } = await searchParams;
  // The reader's month, not the machine's. `new Date()` here is the server's
  // clock, which on Vercel is UTC: for the first three hours of every month
  // in Kuwait that is still the month before, so the calendar opened on
  // September while the phone beside it said October.
  const month =
    parseMonthParam(raw ?? null) ?? startOfMonth(todayIn(await getTimeZone()));
  const { from, to } = monthWindow(month);

  const [profile, page, undated, projects, team] = await Promise.all([
    requireProfile(),
    getTasksDueBetween(from, to),
    // A number, not a list: the page only ever shows how many there are.
    countUndatedTasks(),
    getProjects(),
    getTeam(),
  ]);

  return (
    <CalendarView
      tasks={page.tasks}
      month={monthParam(month)}
      partial={page.truncated}
      undated={undated}
      projects={projects}
      team={team}
      profile={profile}
    />
  );
}
