import { WEEKEND_DAYS, officeClock, type HolidaySet } from "@/lib/work-week";

/**
 * Reading a message sent to the bot as a piece of work.
 *
 *   Call the bank about the mandate tomorrow
 *   !Renew the trade licence
 *   Bring the stamped letter
 *   It is in the second drawer.
 *
 * The first line is the title, anything after it the detail. A "!" in front
 * makes it high priority. "today" or "tomorrow" at the end of the first line —
 * in English, or as the office says it in Arabic — sets when it is due: five
 * in the afternoon, Kuwait time; "tomorrow" means the next working day, as it
 * does in the office.
 */

export type QuickAdd = {
  title: string;
  detail: string | null;
  priority: "medium" | "high";
  /** An ISO instant, or null when no day was named. */
  dueAt: string | null;
};

const TODAY = /(^|\s+)(today|اليوم)\s*[.!]?$/i;
const TOMORROW = /(^|\s+)(tomorrow|باچر|باكر|بكرة|بكره|غدا|غداً)\s*[.!]?$/i;

/** Kuwait keeps UTC+3 all year; see COMPANY_TIME_ZONE. */
const at = (day: string, time: string) => new Date(`${day}T${time}:00+03:00`).toISOString();

function nextWorkingDay(day: string, holidays: HolidaySet): string {
  const cursor = new Date(`${day}T12:00:00Z`);
  do {
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  } while (
    WEEKEND_DAYS.includes(cursor.getUTCDay()) ||
    holidays.has(cursor.toISOString().slice(0, 10))
  );
  return cursor.toISOString().slice(0, 10);
}

export function parseQuickAdd(
  text: string,
  now: Date = new Date(),
  holidays: HolidaySet = new Set(),
): QuickAdd | null {
  const [first = "", ...rest] = text.trim().split(/\r?\n/);
  let title = first.trim();
  const detail = rest.join("\n").trim() || null;

  let priority: QuickAdd["priority"] = "medium";
  if (title.startsWith("!")) {
    priority = "high";
    title = title.replace(/^!+\s*/, "");
  }

  let dueAt: string | null = null;
  const clock = officeClock(now);
  if (TODAY.test(title)) {
    title = title.replace(TODAY, "");
    // Five o'clock, or the end of the day once five has gone.
    dueAt = at(clock.day, clock.hour < 17 ? "17:00" : "23:59");
  } else if (TOMORROW.test(title)) {
    title = title.replace(TOMORROW, "");
    dueAt = at(nextWorkingDay(clock.day, holidays), "17:00");
  }

  title = title.trim().slice(0, 200);
  if (!title) return null;
  return { title, detail, priority, dueAt };
}
