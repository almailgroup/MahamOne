import { describe, expect, it } from "vitest";

import {
  addWorkingDays,
  isWeekend,
  isWorkingDay,
  isoDay,
  nextWorkingDay,
  officeClock,
  onOrAfterWorkingDay,
  quietReason,
  startOfNextWeek,
} from "@/lib/work-week";

/**
 * Kuwait's working week: Sunday to Thursday, Friday and Saturday off.
 * October 2026: Thu 15, Fri 16, Sat 17, Sun 18, Mon 19.
 */
const day = (iso: string) => {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d, 9, 30);
};
const key = (date: Date) => isoDay(date);

describe("the working week", () => {
  it("has Friday and Saturday as its weekend", () => {
    expect(isWeekend(day("2026-10-16"))).toBe(true); // Friday
    expect(isWeekend(day("2026-10-17"))).toBe(true); // Saturday
    expect(isWeekend(day("2026-10-18"))).toBe(false); // Sunday
    expect(isWeekend(day("2026-10-15"))).toBe(false); // Thursday
  });

  it("does not count a company holiday as a working day", () => {
    const eid = new Set(["2026-10-19"]);
    expect(isWorkingDay(day("2026-10-19"))).toBe(true);
    expect(isWorkingDay(day("2026-10-19"), eid)).toBe(false);
  });
});

describe("next working day", () => {
  it("from Thursday is Sunday, over the weekend", () => {
    expect(key(nextWorkingDay(day("2026-10-15")))).toBe("2026-10-18");
  });

  it("from Sunday is Monday", () => {
    expect(key(nextWorkingDay(day("2026-10-18")))).toBe("2026-10-19");
  });

  it("steps over a holiday too", () => {
    const holidays = new Set(["2026-10-18", "2026-10-19"]);
    expect(key(nextWorkingDay(day("2026-10-15"), holidays))).toBe("2026-10-20");
  });

  it("keeps the time of day", () => {
    const next = nextWorkingDay(day("2026-10-15"));
    expect([next.getHours(), next.getMinutes()]).toEqual([9, 30]);
  });
});

describe("working days ahead", () => {
  it("counts three working days from Wednesday as Sunday", () => {
    // Wed 14 → Thu 15, Sun 18, Mon 19
    expect(key(addWorkingDays(day("2026-10-14"), 3))).toBe("2026-10-19");
  });

  it("skips a holiday inside the span", () => {
    const holidays = new Set(["2026-10-18"]);
    // Wed 14 → Thu 15, Mon 19, Tue 20
    expect(key(addWorkingDays(day("2026-10-14"), 3, holidays))).toBe("2026-10-20");
  });
});

describe("start of next week", () => {
  it("is the coming Sunday from any weekday", () => {
    expect(key(startOfNextWeek(day("2026-10-15")))).toBe("2026-10-18"); // Thu
    expect(key(startOfNextWeek(day("2026-10-19")))).toBe("2026-10-25"); // Mon
  });

  it("from a weekend is the Sunday about to start, not the one after", () => {
    expect(key(startOfNextWeek(day("2026-10-16")))).toBe("2026-10-18"); // Fri
    expect(key(startOfNextWeek(day("2026-10-17")))).toBe("2026-10-18"); // Sat
  });

  it("from a Sunday is a week on", () => {
    expect(key(startOfNextWeek(day("2026-10-18")))).toBe("2026-10-25");
  });

  it("moves to Monday when that Sunday is a holiday", () => {
    expect(key(startOfNextWeek(day("2026-10-15"), new Set(["2026-10-18"])))).toBe("2026-10-19");
  });
});

describe("on or after a working day", () => {
  it("leaves a working day alone and moves a weekend day forward", () => {
    expect(key(onOrAfterWorkingDay(day("2026-10-15")))).toBe("2026-10-15");
    expect(key(onOrAfterWorkingDay(day("2026-10-16")))).toBe("2026-10-18");
  });

  it("gives up rather than loop forever on a year of days off", () => {
    const everyDay = new Set(
      Array.from({ length: 400 }, (_, i) => key(new Date(2026, 9, 15 + i))),
    );
    expect(() => onOrAfterWorkingDay(day("2026-10-15"), everyDay)).not.toThrow();
  });
});

describe("the office's clock", () => {
  it("is Kuwait's, three hours ahead of the server's UTC", () => {
    // 05:00 UTC on Sunday is 08:00 in the office: the scheduled run.
    expect(officeClock(new Date("2026-10-18T05:00:00Z"))).toEqual({
      day: "2026-10-18",
      weekday: 0,
      hour: 8,
    });
  });

  it("turns the day over at Kuwait's midnight, not Greenwich's", () => {
    // 22:30 UTC on Saturday is already 01:30 on Sunday.
    expect(officeClock(new Date("2026-10-17T22:30:00Z"))).toMatchObject({
      day: "2026-10-18",
      weekday: 0,
      hour: 1,
    });
  });

  it("calls midnight hour 0, not 24", () => {
    expect(officeClock(new Date("2026-10-17T21:00:00Z")).hour).toBe(0);
  });
});

describe("when reminders stay quiet", () => {
  const at = (iso: string) => officeClock(new Date(iso));

  it("sends on a working morning", () => {
    expect(quietReason(at("2026-10-18T05:00:00Z"))).toBeNull();
  });

  it("not on a Friday or a Saturday", () => {
    expect(quietReason(at("2026-10-16T05:00:00Z"))).toBe("weekend");
    expect(quietReason(at("2026-10-17T05:00:00Z"))).toBe("weekend");
  });

  it("not on a company holiday", () => {
    expect(quietReason(at("2026-10-18T05:00:00Z"), new Set(["2026-10-18"]))).toBe("holiday");
  });

  it("not before seven or from seven in the evening, office time", () => {
    expect(quietReason(at("2026-10-18T03:59:00Z"))).toBe("after_hours"); // 06:59
    expect(quietReason(at("2026-10-18T04:00:00Z"))).toBeNull(); // 07:00
    expect(quietReason(at("2026-10-18T15:59:00Z"))).toBeNull(); // 18:59
    expect(quietReason(at("2026-10-18T16:00:00Z"))).toBe("after_hours"); // 19:00
  });
});
