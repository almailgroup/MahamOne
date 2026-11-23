import { describe, expect, it, test } from "vitest";

import {
  compactAge,
  daysBetween,
  describeDayGap,
  describeDayGapDetail,
  formatElapsed,
  formatTimeOfDay,
  isoFromLocalInput,
  relativeDay,
  toLocalInput,
} from "@/lib/dates";

describe("isoFromLocalInput", () => {
  /**
   * The bug this exists to prevent: the value from <input type="datetime-local">
   * carries no offset, so parsing it anywhere but the viewer's machine reads it
   * in the wrong zone. It was being parsed server-side, where local is UTC, and
   * every due date entered in Dubai came back four hours late.
   *
   * The suite runs in UTC, so this asserts the conversion is anchored to the
   * running process's zone rather than assuming one.
   */
  it("resolves wall-clock input against the local zone", () => {
    expect(isoFromLocalInput("2026-09-15T17:30")).toBe("2026-09-15T17:30:00.000Z");
  });

  it("round-trips through toLocalInput without drift", () => {
    const typed = "2026-09-15T17:30";
    const iso = isoFromLocalInput(typed);
    expect(iso).not.toBeNull();
    expect(toLocalInput(iso)).toBe(typed);
  });

  it("returns null for empty and unparseable values", () => {
    expect(isoFromLocalInput("")).toBeNull();
    expect(isoFromLocalInput("   ")).toBeNull();
    expect(isoFromLocalInput("not a date")).toBeNull();
  });
});

describe("compactAge", () => {
  const base = Date.parse("2026-09-15T12:00:00.000Z");
  const ago = (ms: number) => new Date(base - ms).toISOString();

  it("steps through seconds, minutes, hours, days and weeks", () => {
    expect(compactAge(ago(5_000), base)).toBe("5s");
    expect(compactAge(ago(90_000), base)).toBe("1m");
    expect(compactAge(ago(3 * 3600_000), base)).toBe("3h");
    expect(compactAge(ago(3 * 86400_000), base)).toBe("3d");
    expect(compactAge(ago(14 * 86400_000), base)).toBe("2w");
  });

  it("never goes negative for a clock that is behind", () => {
    expect(compactAge(new Date(base + 60_000).toISOString(), base)).toBe("0s");
  });
});

describe("formatElapsed", () => {
  it("does not wrap hours into days", () => {
    const base = Date.parse("2026-09-15T12:00:00.000Z");
    const from = new Date(base - (72 * 3600_000 + 7 * 60_000 + 4_000)).toISOString();
    expect(formatElapsed(from, base)).toBe("72:07:04");
  });
});

describe("relativeDay", () => {
  it("names today, tomorrow and yesterday", () => {
    const now = new Date();
    const day = (offset: number) => {
      const d = new Date(now);
      d.setDate(d.getDate() + offset);
      return d.toISOString();
    };
    expect(relativeDay(day(0))).toBe("today");
    expect(relativeDay(day(1))).toBe("tomorrow");
    expect(relativeDay(day(-1))).toBe("yesterday");
  });
});

describe("daysBetween", () => {
  const d = (iso: string) => new Date(iso);

  it("counts calendar days, not elapsed hours", () => {
    // 23 hours apart, but a different calendar day: that is one day.
    expect(daysBetween(d("2026-09-15T23:30:00"), d("2026-09-16T22:30:00"))).toBe(1);
    expect(daysBetween(d("2026-09-15T00:01:00"), d("2026-09-15T23:59:00"))).toBe(0);
  });

  it("is negative for the past and symmetric", () => {
    const a = d("2026-09-15T12:00:00");
    const b = d("2026-09-27T12:00:00");
    expect(daysBetween(a, b)).toBe(12);
    expect(daysBetween(b, a)).toBe(-12);
  });

  it("crosses month and year boundaries", () => {
    expect(daysBetween(d("2026-12-28T12:00:00"), d("2027-01-04T12:00:00"))).toBe(7);
    expect(daysBetween(d("2026-02-27T12:00:00"), d("2026-03-01T12:00:00"))).toBe(2);
  });

  it("counts the leap day in 2028", () => {
    expect(daysBetween(d("2028-02-27T12:00:00"), d("2028-03-01T12:00:00"))).toBe(3);
  });

  /**
   * The reason this is projected onto UTC rather than subtracted directly: on
   * a spring-forward day the local day is 23 hours long, so a millisecond
   * difference divided by 86,400,000 gives 6.958 for a week — which floors to
   * 6 and reports the wrong number of days.
   */
  it("is exact across a daylight-saving change", () => {
    const previous = process.env.TZ;
    process.env.TZ = "Europe/London";
    try {
      // British Summer Time began on 29 March 2026.
      expect(daysBetween(new Date(2026, 2, 26, 12), new Date(2026, 3, 2, 12))).toBe(7);
      expect(daysBetween(new Date(2026, 2, 28, 12), new Date(2026, 2, 29, 12))).toBe(1);
    } finally {
      process.env.TZ = previous;
    }
  });
});

describe("describeDayGap", () => {
  it("names the three days nobody wants counted", () => {
    expect(describeDayGap(0)).toBe("Today");
    expect(describeDayGap(1)).toBe("Tomorrow");
    expect(describeDayGap(-1)).toBe("Yesterday");
  });

  it("counts forwards and backwards", () => {
    expect(describeDayGap(12)).toBe("In 12 days");
    expect(describeDayGap(-9)).toBe("9 days ago");
  });
});

describe("describeDayGapDetail", () => {
  it("stays quiet under a fortnight, where the day count is already clear", () => {
    expect(describeDayGapDetail(13)).toBeNull();
    expect(describeDayGapDetail(0)).toBeNull();
  });

  it("breaks a longer gap into weeks and days, singular where it should be", () => {
    expect(describeDayGapDetail(14)).toBe("2 weeks");
    expect(describeDayGapDetail(15)).toBe("2 weeks, 1 day");
    expect(describeDayGapDetail(30)).toBe("4 weeks, 2 days");
    expect(describeDayGapDetail(-21)).toBe("3 weeks");
  });
});

describe("the time of day on its own", () => {
  const DUBAI = "Asia/Dubai";
  const iso = "2026-09-16T04:05:00Z"; // 08:05 in Dubai

  test("reads in the viewer's timezone, not the server's", () => {
    expect(formatTimeOfDay(iso, "en-AE", DUBAI)).toMatch(/8:05/);
    expect(formatTimeOfDay(iso, "en-AE", "UTC")).toMatch(/4:05/);
  });

  test("says which half of the day it is by default", () => {
    expect(formatTimeOfDay(iso, "en-AE", DUBAI)).toMatch(/AM/i);
  });

  test("`bare` drops it, and takes nothing else with it", () => {
    expect(formatTimeOfDay(iso, "en-AE", DUBAI, { bare: true })).toBe("8:05");
  });

  test("`bare` drops the Arabic marker too, rather than cutting English off a string", () => {
    // ar-AE-u-nu-latn is what the app asks for: Arabic, Latin digits. The
    // marker is ص, so a `replace(/AM|PM/)` would have left it in place.
    const full = formatTimeOfDay(iso, "ar-AE-u-nu-latn", DUBAI);
    const bare = formatTimeOfDay(iso, "ar-AE-u-nu-latn", DUBAI, { bare: true });
    expect(full).toContain("ص");
    expect(bare).toBe("8:05");
  });
});
