/**
 * The scheduled run: what it does on a working morning, and what it leaves
 * alone on a day off.
 *
 * The server's jobs are a stand-in that records which were run, so the
 * question each test asks is "did this run tell anybody anything".
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

import type { QueuedReminder } from "@/lib/reminders/types";

vi.mock("server-only", () => ({}));
const sendClaimed = vi.fn(async (_db: unknown, claimed: QueuedReminder[]) => ({
  considered: claimed.length,
  sent: claimed.length,
  retrying: 0,
  givenUp: 0,
}));
vi.mock("@/lib/reminders/dispatch", () => ({
  sendClaimed: (db: unknown, claimed: QueuedReminder[]) => sendClaimed(db, claimed),
}));
const alertAdmins = vi.fn(async () => 1);
vi.mock("@/lib/reminders/admin-alerts", () => ({ alertAdmins: () => alertAdmins() }));

const { sweep } = await import("@/lib/reminders/sweep");

/** Which of the server's jobs ran, in order. */
let called: string[];
/** What the holiday job was asked about. */
let holidayAsks: Record<string, unknown>[];
let holidays: string[];
let holidayError: { code?: string; message: string } | null;
let summaryError: { code?: string; message: string } | null;

function fakeServer() {
  return {
    rpc: async (job: string, args: Record<string, unknown> = {}) => {
      called.push(job);
      if (job === "holidays") {
        holidayAsks.push(args);
        if (holidayError) return { data: null, error: holidayError };
        // The company holidays from p_from to p_to, both included.
        const from = String(args.p_from);
        const to = String(args.p_to);
        return {
          data: holidays.filter((day) => day >= from && day <= to).map((day) => ({ day })),
          error: null,
        };
      }
      if (job === "enqueue_morning_summaries") {
        return summaryError ? { data: null, error: summaryError } : { data: 2, error: null };
      }
      if (job === "claim_reminders") return { data: [{ id: "r1" }], error: null };
      return { data: null, error: null };
    },
  } as never;
}

const SUNDAY_8AM = new Date("2026-10-18T05:00:00Z");
const SUNDAY_2PM = new Date("2026-10-18T11:00:00Z");
const FRIDAY_8AM = new Date("2026-10-16T05:00:00Z");
const SUNDAY_3AM = new Date("2026-10-18T00:00:00Z");

beforeEach(() => {
  called = [];
  holidayAsks = [];
  holidays = [];
  holidayError = null;
  summaryError = null;
  sendClaimed.mockClear();
  alertAdmins.mockClear();
});

describe("a working morning", () => {
  test("queues what is due, the summaries, and sends", async () => {
    const result = await sweep(fakeServer(), SUNDAY_8AM);

    expect(called).toEqual([
      "purge_trashed_tasks",
      "purge_old_errors",
      "holidays",
      "enqueue_task_reminders",
      "enqueue_morning_summaries",
      "claim_reminders",
    ]);
    expect(result).toMatchObject({ quiet: null, summaries: 2, sent: 1 });
  });

  test("an afternoon run sends reminders but no morning summary", async () => {
    await sweep(fakeServer(), SUNDAY_2PM);
    expect(called).toContain("enqueue_task_reminders");
    expect(called).not.toContain("enqueue_morning_summaries");
  });

  test("before migration 37, the missing summary function is not an error", async () => {
    summaryError = { code: "PGRST202", message: "Could not find the function" };
    const log = vi.spyOn(console, "error").mockImplementation(() => {});

    const result = await sweep(fakeServer(), SUNDAY_8AM);

    expect(result).toMatchObject({ summaries: 0, sent: 1 });
    expect(log).not.toHaveBeenCalled();
    log.mockRestore();
  });
});

describe("a day off", () => {
  test.each([
    ["a Friday", FRIDAY_8AM, "weekend"],
    ["the middle of the night", SUNDAY_3AM, "after_hours"],
  ])("on %s nobody is told anything, but the tidying still happens", async (_, when, why) => {
    const result = await sweep(fakeServer(), when);

    expect(result.quiet).toBe(why);
    // Reading the holiday list tells nobody anything either.
    expect(called).toEqual(["purge_trashed_tasks", "purge_old_errors", "holidays"]);
    expect(sendClaimed).not.toHaveBeenCalled();
  });

  test("a company holiday is a day off", async () => {
    holidays = ["2026-10-18"];
    const result = await sweep(fakeServer(), SUNDAY_8AM);

    expect(result.quiet).toBe("holiday");
    expect(called).not.toContain("claim_reminders");
    // Asked about the office's day, and that day only.
    expect(holidayAsks).toEqual([{ p_from: "2026-10-18", p_to: "2026-10-18" }]);
  });

  test("a holiday on another day does not quieten this one", async () => {
    holidays = ["2026-10-19"];
    const result = await sweep(fakeServer(), SUNDAY_8AM);

    expect(result.quiet).toBeNull();
    expect(called).toContain("claim_reminders");
  });

  test("an unreadable holiday list does not hold back a working day", async () => {
    holidayError = { code: "PGRST202", message: "Could not find the function" };
    const result = await sweep(fakeServer(), SUNDAY_8AM);

    expect(result.quiet).toBeNull();
    expect(called).toContain("claim_reminders");
  });
});

describe("telling the admins about faults", () => {
  test("happens on a working morning, after the reminders", async () => {
    const result = await sweep(fakeServer(), SUNDAY_8AM);
    expect(alertAdmins).toHaveBeenCalledTimes(1);
    expect(result.alerted).toBe(1);
  });

  test("waits for the office to open, like everything else that reaches a person", async () => {
    await sweep(fakeServer(), FRIDAY_8AM);
    await sweep(fakeServer(), SUNDAY_3AM);
    expect(alertAdmins).not.toHaveBeenCalled();
  });

  test("is never the reason a run fails", async () => {
    alertAdmins.mockRejectedValueOnce(new Error("telegram down"));
    const errors = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const result = await sweep(fakeServer(), SUNDAY_8AM);
    expect(result).toMatchObject({ sent: 1, alerted: 0 });
    errors.mockRestore();
  });
});
