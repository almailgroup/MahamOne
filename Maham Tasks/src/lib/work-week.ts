/**
 * The company's working week, and the days off within it.
 *
 * Almailgroup works Sunday to Thursday, as Kuwait does; Friday and Saturday
 * are the weekend. Everything that reasons about "a working day" — the date
 * shortcuts, the calendar's shading, whether a reminder goes out — asks here,
 * so they cannot disagree about which days count.
 *
 * Dates here are floating local dates (midnight on a wall calendar, as in
 * lib/calendar), and holidays are matched on their ISO day, "2026-03-20".
 */

/** The day a week starts on, in `Date.getDay()` numbering: Sunday. */
export const FIRST_DAY_OF_WEEK = 0;

/** Friday and Saturday, in `Date.getDay()` numbering. */
export const WEEKEND_DAYS: readonly number[] = [5, 6];

/** Company holidays as ISO days, "2026-03-20". */
export type HolidaySet = ReadonlySet<string>;

const NO_HOLIDAYS: HolidaySet = new Set();

/** A local date as "2026-03-20" — the key holidays are stored and matched by. */
export function isoDay(date: Date): string {
  const pad = (n: number) => `${n}`.padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function isWeekend(date: Date): boolean {
  return WEEKEND_DAYS.includes(date.getDay());
}

export function isHoliday(date: Date, holidays: HolidaySet = NO_HOLIDAYS): boolean {
  return holidays.has(isoDay(date));
}

export function isWorkingDay(date: Date, holidays: HolidaySet = NO_HOLIDAYS): boolean {
  return !isWeekend(date) && !isHoliday(date, holidays);
}

/** The same calendar date `days` later, keeping the time of day. */
function plusDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

/**
 * The date itself if it is a working day, otherwise the next one that is.
 *
 * Bounded: a year of days off in a row is a data error, not a calendar, and
 * a loop that never ends would hang the page rather than say so.
 */
export function onOrAfterWorkingDay(date: Date, holidays: HolidaySet = NO_HOLIDAYS): Date {
  let day = new Date(date);
  for (let i = 0; i < 366 && !isWorkingDay(day, holidays); i++) day = plusDays(day, 1);
  return day;
}

/** The first working day strictly after `from`. */
export function nextWorkingDay(from: Date, holidays: HolidaySet = NO_HOLIDAYS): Date {
  return onOrAfterWorkingDay(plusDays(from, 1), holidays);
}

/** `count` working days after `from`, not counting `from` itself. */
export function addWorkingDays(
  from: Date,
  count: number,
  holidays: HolidaySet = NO_HOLIDAYS,
): Date {
  let day = new Date(from);
  for (let i = 0; i < count; i++) day = nextWorkingDay(day, holidays);
  return day;
}

/**
 * The first working day of next week: Sunday, unless Sunday is a holiday.
 * From a Friday or Saturday that is the day after the weekend — the week that
 * is about to start, not the one after it.
 */
export function startOfNextWeek(from: Date, holidays: HolidaySet = NO_HOLIDAYS): Date {
  const daysUntil = (FIRST_DAY_OF_WEEK - from.getDay() + 7) % 7 || 7;
  return onOrAfterWorkingDay(plusDays(from, daysUntil), holidays);
}

// ---------------------------------------------------------------------------
// The office's clock, for things that happen on their own: reminders and the
// morning summary are sent by a server whose clock is UTC, to people whose
// day is Kuwait's.
// ---------------------------------------------------------------------------

/**
 * Kuwait keeps no summer time, so this is UTC+3 all year. Named rather than
 * written as an offset so the arithmetic is the platform's. The database
 * has the same, as public.company_time_zone().
 */
export const COMPANY_TIME_ZONE = "Asia/Kuwait";

/** Reminders go out from 07:00 until 19:00, office time, on working days. */
export const OFFICE_HOURS = { from: 7, until: 19 } as const;

/**
 * The summary goes out with the first run of a working morning, and not
 * after noon: one that turns up mid-afternoon, because the first run that
 * day was late, is a list of things already being done.
 */
export const SUMMARY_UNTIL_HOUR = 12;

/** Which day and hour it is in the office. `weekday` is `Date.getDay()` numbering. */
export type OfficeClock = { day: string; weekday: number; hour: number };

export function officeClock(at: Date, timeZone: string = COMPANY_TIME_ZONE): OfficeClock {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(at);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === type)?.value ?? "";
  const day = `${part("year")}-${part("month")}-${part("day")}`;
  return {
    day,
    weekday: new Date(`${day}T12:00:00Z`).getUTCDay(),
    hour: Number(part("hour")),
  };
}

export type QuietReason = "weekend" | "holiday" | "after_hours";

/**
 * Why nothing should be sent now, or null when it is office time on a
 * working day.
 */
export function quietReason(
  clock: OfficeClock,
  holidays: HolidaySet = NO_HOLIDAYS,
): QuietReason | null {
  if (WEEKEND_DAYS.includes(clock.weekday)) return "weekend";
  if (holidays.has(clock.day)) return "holiday";
  if (clock.hour < OFFICE_HOURS.from || clock.hour >= OFFICE_HOURS.until) return "after_hours";
  return null;
}
