/**
 * The window a "due today" query asks the database for.
 *
 * "Today" is the reader's calendar day, and a query can only speak in
 * instants, so the two have to agree exactly. A boundary an hour out shows
 * yesterday's late work as due today, four hours east of UTC.
 */

import { describe, expect, test } from "vitest";

import { dayBoundsIn, isDueToday } from "@/lib/dates";

describe("dayBoundsIn", () => {
  test("Kuwait's day starts at 21:00 UTC the evening before", () => {
    const { start, end } = dayBoundsIn(new Date("2026-09-21T09:00:00Z"), "Asia/Kuwait");
    expect(start).toBe("2026-09-20T21:00:00.000Z");
    expect(end).toBe("2026-09-21T21:00:00.000Z");
  });

  test("UTC's day is the plain one", () => {
    const { start, end } = dayBoundsIn(new Date("2026-09-21T09:00:00Z"), "UTC");
    expect(start).toBe("2026-09-21T00:00:00.000Z");
    expect(end).toBe("2026-09-22T00:00:00.000Z");
  });

  test("a zone behind UTC starts later in the UTC day", () => {
    const { start } = dayBoundsIn(new Date("2026-09-21T18:00:00Z"), "America/New_York");
    expect(start).toBe("2026-09-21T04:00:00.000Z");
  });

  test("an instant late in the Kuwait evening is still that day", () => {
    // 22:00 UTC on the 20th is 01:00 on the 21st in Kuwait.
    const { start, end } = dayBoundsIn(new Date("2026-09-20T22:00:00Z"), "Asia/Kuwait");
    expect(start).toBe("2026-09-20T21:00:00.000Z");
    expect(end).toBe("2026-09-21T21:00:00.000Z");
  });

  test("the window agrees with isDueToday at both edges", () => {
    // The real clock, not a pinned instant: isDueToday asks what day it is
    // now, so a fixed date here would compare two different days and fail
    // for a reason that has nothing to do with the boundary.
    const { start, end } = dayBoundsIn(new Date(), "Asia/Kuwait");

    const justInside = new Date(new Date(start).getTime() + 1000).toISOString();
    const justOutside = new Date(new Date(start).getTime() - 1000).toISOString();
    const lastSecond = new Date(new Date(end).getTime() - 1000).toISOString();
    const justAfter = new Date(new Date(end).getTime() + 1000).toISOString();

    expect(isDueToday(justInside, "Asia/Kuwait")).toBe(true);
    expect(isDueToday(lastSecond, "Asia/Kuwait")).toBe(true);
    expect(isDueToday(justOutside, "Asia/Kuwait")).toBe(false);
    expect(isDueToday(justAfter, "Asia/Kuwait")).toBe(false);
  });
});
