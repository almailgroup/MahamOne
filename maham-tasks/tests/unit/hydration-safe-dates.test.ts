import { describe, expect, it } from "vitest";

import { createTranslator, localeTag } from "@/lib/i18n";
import { daysAgo, formatDateTime, isDueToday, relativeDay } from "@/lib/dates";
import { dayKeyIn } from "@/lib/calendar";

/**
 * A date is written twice — once on the server and once in the browser — and
 * the two have to come out identical or React throws the server's markup away
 * (hydration error #418).
 *
 * They used to disagree twice over: `toLocaleString` with no arguments asks
 * the runtime for the locale (en-US on Vercel, en-GB in the browser here) and
 * for the timezone (UTC on Vercel, +04 here). A task due at 22:00 UTC was
 * "Sep 15, 10:00 PM" on one side and "16 Sept, 2:00" on the other.
 *
 * Every helper below now takes both from the translator, so the answer depends
 * on the reader rather than on the machine. These tests pin that: given the
 * same arguments, the output cannot move.
 */

/** 22:00 UTC on the 15th — 02:00 on the 16th in Dubai, so the day differs. */
const lateEvening = "2026-09-15T22:00:00.000Z";

describe("formatDateTime", () => {
  it("honours the timezone it is given rather than the machine's", () => {
    const tag = localeTag("en");
    expect(formatDateTime(lateEvening, tag, "UTC")).toBe("15 Sep, 10:00 PM");
    expect(formatDateTime(lateEvening, tag, "Asia/Dubai")).toBe("16 Sep, 2:00 AM");
  });

  it("writes the same string every time, whatever the runtime", () => {
    const en = createTranslator("en", "Asia/Dubai");
    const first = formatDateTime(lateEvening, en.tag, en.timeZone);
    for (let i = 0; i < 5; i += 1) {
      expect(formatDateTime(lateEvening, en.tag, en.timeZone)).toBe(first);
    }
  });

  it("gives Arabic the same instant in Western digits", () => {
    const ar = createTranslator("ar", "Asia/Dubai");
    const text = formatDateTime(lateEvening, ar.tag, ar.timeZone);
    expect(text).toContain("16");
    expect(text).toMatch(/[\u0600-\u06FF]/);
    // Eastern Arabic numerals would defeat the point of pinning nu-latn.
    expect(text).not.toMatch(/[\u0660-\u0669]/);
  });
});

describe("the viewer's calendar day", () => {
  it("buckets an instant by the reader's zone, not the server's", () => {
    const instant = new Date(lateEvening);
    expect(dayKeyIn(instant, "UTC")).toBe("2026-8-15");
    expect(dayKeyIn(instant, "Asia/Dubai")).toBe("2026-8-16");
    // A reader behind UTC is on the same day here, and must not be assumed to
    // shift the same way as one ahead of it.
    expect(dayKeyIn(instant, "America/New_York")).toBe("2026-8-15");
  });

  it("answers 'is this due today' from the reader's zone", () => {
    const now = new Date();
    const inDubai = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Dubai",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now);

    expect(isDueToday(now.toISOString(), "Asia/Dubai")).toBe(true);
    expect(isDueToday(null, "Asia/Dubai")).toBe(false);

    // Midday on the same Dubai date is still today, whatever UTC calls it.
    expect(isDueToday(`${inDubai}T12:00:00+04:00`, "Asia/Dubai")).toBe(true);
  });

  it("counts whole days from the reader's midnight", () => {
    const now = Date.now();
    const day = 86_400_000;
    expect(daysAgo(new Date(now).toISOString(), "Asia/Dubai")).toBe(0);
    expect(daysAgo(new Date(now - 2 * day).toISOString(), "Asia/Dubai")).toBe(2);
    expect(daysAgo(new Date(now + day).toISOString(), "Asia/Dubai")).toBe(-1);
  });

  it("phrases the gap in words from the same reckoning", () => {
    const en = createTranslator("en", "Asia/Dubai");
    const day = 86_400_000;
    expect(relativeDay(new Date().toISOString(), en)).toBe("today");
    expect(relativeDay(new Date(Date.now() + day).toISOString(), en)).toBe("tomorrow");
    expect(relativeDay(new Date(Date.now() - day).toISOString(), en)).toBe("yesterday");
  });
});
