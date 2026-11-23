import { FIRST_DAY_OF_WEEK } from "@/lib/work-week";

/**
 * Calendar arithmetic, in the viewer's own timezone.
 *
 * Everything here works on local calendar days, not instants: a task due at
 * 01:00 on Tuesday belongs on Tuesday's square whatever the offset is, and
 * ISO strings would put it on Monday for anyone east of Greenwich.
 */

export function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

/** A stable per-day key: ISO would shift with the timezone at the boundary. */
export function dayKey(date: Date): string {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

/**
 * The grid cell an *instant* belongs in, in the viewer's zone.
 *
 * The cells themselves are floating dates — midnight on a wall calendar, with
 * no zone of their own — and `dayKey` is right for those. A due date is not:
 * it is a moment, and which square it lands on depends on where the reader is.
 * Asking the runtime instead put a task due at 22:00 UTC on the 15th for the
 * server and the 16th for a browser in Dubai, so the two renders drew
 * different calendars.
 */
export function dayKeyIn(date: Date, timeZone?: string): string {
  const [year, month, day] = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
    .format(date)
    .split("-")
    .map(Number);
  return `${year}-${month - 1}-${day}`;
}

/** Today as a floating date, on the viewer's calendar rather than the machine's. */
export function todayIn(timeZone?: string): Date {
  const [year, month, day] = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
    .format(new Date())
    .split("-")
    .map(Number);
  return new Date(year, month - 1, day);
}

export function isSameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

export function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function addMonths(date: Date, delta: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + delta, 1);
}

/**
 * Where a day sits in the company's week, 0–6. The week starts on Sunday, as
 * Kuwait's does (lib/work-week); `getDay()` happens to number it the same way,
 * but the start day is read from there so the two can never drift apart.
 */
export function weekdayIndex(date: Date): number {
  return (date.getDay() - FIRST_DAY_OF_WEEK + 7) % 7;
}

/**
 * Weekday names in the reader's language, in the company's week order, from
 * Intl rather than a dictionary — abbreviations are a per-language matter, and
 * Arabic has none. 2024-01-07 was a Sunday.
 */
export function weekdayLabels(
  tag: string | undefined,
  style: "long" | "short" | "narrow" = "short",
): string[] {
  const format = new Intl.DateTimeFormat(tag, { weekday: style });
  return Array.from({ length: 7 }, (_, index) =>
    format.format(new Date(2024, 0, 7 + FIRST_DAY_OF_WEEK + index)),
  );
}

/**
 * The six-week grid for a month, from the first day of the company's week,
 * padded with the adjacent months' days so every row is full and the grid
 * never changes height.
 */
export function monthGrid(month: Date): Date[] {
  const first = startOfMonth(month);
  const start = new Date(first);
  start.setDate(first.getDate() - weekdayIndex(first));

  return Array.from({ length: 42 }, (_, index) => {
    const day = new Date(start);
    day.setDate(start.getDate() + index);
    return day;
  });
}

/** `2026-09` → the first of that month; anything else → null. */
export function parseMonthParam(value: string | null): Date | null {
  const match = value?.match(/^(\d{4})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]) - 1;
  if (month < 0 || month > 11) return null;
  return new Date(year, month, 1);
}

export function monthParam(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

/**
 * The instants a month's grid covers, as a query wants them.
 *
 * The grid is six weeks, not a month: the last days of August sit on
 * September's page and a task due on one of them belongs in September's
 * answer. Widened by a day at each end so that a viewer whose timezone is
 * ahead of the server's still gets the task that lands on their first or
 * last square.
 */
export function monthWindow(month: Date): { from: string; to: string } {
  const days = monthGrid(month);
  const from = new Date(days[0]);
  from.setDate(from.getDate() - 1);
  const to = new Date(days[days.length - 1]);
  to.setDate(to.getDate() + 2);

  return { from: from.toISOString(), to: to.toISOString() };
}
