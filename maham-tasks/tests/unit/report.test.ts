import { describe, expect, it } from "vitest";

import { niceMax, onTimeRate, reportRange } from "@/lib/report";

/** Saturday 17 October 2026, 23:30 in Kuwait — still the 17th there. */
const LATE_SATURDAY = new Date("2026-10-17T20:30:00Z");
/** Sunday 18 October, 00:30 in Kuwait, but the 17th in UTC. */
const SUNDAY_JUST_AFTER_MIDNIGHT = new Date("2026-10-17T21:30:00Z");

describe("the report's periods", () => {
  it("end today, office time", () => {
    expect(reportRange("4w", LATE_SATURDAY)).toEqual({
      period: "4w",
      first: "2026-09-20",
      last: "2026-10-17",
      grain: "week",
    });
    expect(reportRange("4w", SUNDAY_JUST_AFTER_MIDNIGHT).last).toBe("2026-10-18");
  });

  it("twelve weeks is eighty-four days, by week", () => {
    expect(reportRange("12w", LATE_SATURDAY)).toMatchObject({ first: "2026-07-26", grain: "week" });
  });

  it("this year starts on the first of January, by month", () => {
    expect(reportRange("year", LATE_SATURDAY)).toMatchObject({ first: "2026-01-01", grain: "month" });
  });
});

describe("the numbers on it", () => {
  it("says nothing about on-time with nothing that had a due date", () => {
    expect(onTimeRate(0, 0)).toBeNull();
    expect(onTimeRate(3, 4)).toBe(75);
  });

  it("tops an axis at a clean number", () => {
    expect([0, 3, 7, 12, 23, 48, 130].map(niceMax)).toEqual([4, 4, 10, 20, 25, 50, 200]);
  });
});
