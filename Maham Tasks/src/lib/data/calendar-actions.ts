"use server";

import { getTasksDueBetween } from "@/lib/data/queries";
import { monthWindow, parseMonthParam } from "@/lib/calendar";
import type { TaskPage } from "@/lib/data/queries";

/**
 * One month of due dates, fetched when the calendar is turned to it.
 *
 * The alternative was to make every month change a navigation, which is a
 * server render and a skeleton flash for what reads as flipping a page. This
 * fetches only the month's own window — so the query is bounded however many
 * years of work the portal holds — and the view keeps what it has already
 * seen, so flipping back is free.
 *
 * Row-level security decides what comes back, exactly as on the page itself:
 * this runs as the signed-in user, not as the service role.
 */
export async function tasksForMonth(month: string): Promise<TaskPage> {
  const parsed = parseMonthParam(month);
  if (!parsed) return { tasks: [], total: 0, truncated: false };

  const { from, to } = monthWindow(parsed);
  return getTasksDueBetween(from, to);
}
