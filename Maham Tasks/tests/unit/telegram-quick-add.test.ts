import { describe, expect, it } from "vitest";

import { parseQuickAdd } from "@/lib/telegram/quick-add";

/** Sunday 18 October 2026, ten in the morning in Kuwait. */
const SUNDAY_10AM = new Date("2026-10-18T07:00:00Z");
/** Thursday 15 October, ten in the morning: tomorrow is the weekend. */
const THURSDAY_10AM = new Date("2026-10-15T07:00:00Z");

describe("a message to the bot, as a piece of work", () => {
  it("takes the first line as the title and the rest as the detail", () => {
    expect(parseQuickAdd("Bring the stamped letter\nIt is in the second drawer.", SUNDAY_10AM)).toEqual({
      title: "Bring the stamped letter",
      detail: "It is in the second drawer.",
      priority: "medium",
      dueAt: null,
    });
  });

  it("makes it high priority with a ! in front", () => {
    expect(parseQuickAdd("!Renew the trade licence", SUNDAY_10AM)).toMatchObject({
      title: "Renew the trade licence",
      priority: "high",
    });
  });

  it("is due at five today when it says today", () => {
    expect(parseQuickAdd("Call the bank today", SUNDAY_10AM)).toMatchObject({
      title: "Call the bank",
      dueAt: "2026-10-18T14:00:00.000Z",
    });
  });

  it("…or at the end of the day once five has gone", () => {
    const evening = new Date("2026-10-18T15:30:00Z"); // 18:30 in Kuwait
    expect(parseQuickAdd("Call the bank today", evening)?.dueAt).toBe("2026-10-18T20:59:00.000Z");
  });

  it("takes tomorrow as the next working day", () => {
    expect(parseQuickAdd("Send the invoice tomorrow", SUNDAY_10AM)?.dueAt).toBe("2026-10-19T14:00:00.000Z");
    // From a Thursday that is Sunday, not Friday.
    expect(parseQuickAdd("Send the invoice tomorrow", THURSDAY_10AM)?.dueAt).toBe("2026-10-18T14:00:00.000Z");
  });

  it("steps over a company holiday", () => {
    const holidays = new Set(["2026-10-19"]);
    expect(parseQuickAdd("Send the invoice tomorrow", SUNDAY_10AM, holidays)?.dueAt).toBe(
      "2026-10-20T14:00:00.000Z",
    );
  });

  it("understands the office's Arabic", () => {
    expect(parseQuickAdd("اتصل بالبنك باچر", SUNDAY_10AM)).toMatchObject({
      title: "اتصل بالبنك",
      dueAt: "2026-10-19T14:00:00.000Z",
    });
    expect(parseQuickAdd("راجع العقد اليوم", SUNDAY_10AM)).toMatchObject({
      title: "راجع العقد",
      dueAt: "2026-10-18T14:00:00.000Z",
    });
  });

  it("leaves a day in the middle of a sentence alone", () => {
    expect(parseQuickAdd("Ask why today's delivery was late", SUNDAY_10AM)).toMatchObject({
      title: "Ask why today's delivery was late",
      dueAt: null,
    });
  });

  it("is nothing when there is nothing to add", () => {
    expect(parseQuickAdd("   ", SUNDAY_10AM)).toBeNull();
    expect(parseQuickAdd("! today", SUNDAY_10AM)).toBeNull();
  });
});
