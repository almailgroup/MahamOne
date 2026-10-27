import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { quickDateOptions } from "@/lib/dates";
import { createTranslator } from "@/lib/i18n";

/**
 * The date shortcuts count in Kuwait's working week. Thursday 15 October 2026
 * is the case the old ones got wrong: "Tomorrow" was a Friday.
 */
const speaker = createTranslator("en");
const local = (iso: string) => {
  const d = new Date(iso);
  const pad = (n: number) => `${n}`.padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:00 ${d.toLocaleDateString("en", { weekday: "short" })}`;
};
const pick = (options: ReturnType<typeof quickDateOptions>, key: string) =>
  local(options.find((o) => o.key === key)!.value());

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(2026, 9, 15, 11, 0)); // Thursday, 11:00 local
});
afterEach(() => vi.useRealTimers());

describe("due-date shortcuts on a Thursday", () => {
  it("offer the working-day choices, in the order people reach for them", () => {
    expect(quickDateOptions(speaker).map((o) => o.label)).toEqual([
      "Later today",
      "Next working day",
      "In 3 working days",
      "Start of next week",
      "In a week",
    ]);
  });

  it("put the next working day on Sunday, past the weekend", () => {
    expect(pick(quickDateOptions(speaker), "nextWorkingDay")).toBe("2026-10-18 17:00 Sun");
  });

  it("count three working days as Sunday, Monday, Tuesday", () => {
    expect(pick(quickDateOptions(speaker), "in3WorkingDays")).toBe("2026-10-20 17:00 Tue");
  });

  it("start next week first thing on Sunday", () => {
    expect(pick(quickDateOptions(speaker), "nextWeek")).toBe("2026-10-18 09:00 Sun");
  });

  it("step around a company holiday", () => {
    const holidays = new Set(["2026-10-18"]);
    expect(pick(quickDateOptions(speaker, holidays), "nextWorkingDay")).toBe("2026-10-19 17:00 Mon");
    expect(pick(quickDateOptions(speaker, holidays), "nextWeek")).toBe("2026-10-19 09:00 Mon");
  });

  it("give follow-ups a morning hour and no 'later today'", () => {
    const followUps = quickDateOptions(speaker, new Set(), { hour: 9, includeToday: false });
    expect(followUps.map((o) => o.key)).not.toContain("laterToday");
    expect(pick(followUps, "nextWorkingDay")).toBe("2026-10-18 09:00 Sun");
  });
});
