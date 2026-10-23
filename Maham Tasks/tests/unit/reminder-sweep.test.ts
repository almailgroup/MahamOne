/**
 * The scheduled run: what it does on a working morning, and what it leaves
 * alone on a day off.
 *
 * The database is a stand-in that records which functions were called, so
 * the question each test asks is "did this run tell anybody anything".
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
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => ({}) }));
const alertAdmins = vi.fn(async () => 1);
vi.mock("@/lib/reminders/admin-alerts", () => ({ alertAdmins: () => alertAdmins() }));

const { sweep } = await import("@/lib/reminders/sweep");

/** Which RPCs ran, in order. */
let called: string[];
let holidays: string[];
let holidayError: { code?: string; message: string } | null;
let summaryError: { code?: string; message: string } | null;

function fakeAdmin() {
  return {
    rpc: async (name: string) => {
      called.push(name);
      if (name === "enqueue_morning_summaries") {
        return summaryError ? { data: null, error: summaryError } : { data: 2, error: null };
      }
      if (name === "claim_reminders") return { data: [{ id: "r1" }], error: null };
      return { data: null, error: null };
    },
    from: () => ({
      select: () => ({
        eq: async (_column: string, day: string) =>
          holidayError
            ? { data: null, error: holidayError }
            : { data: holidays.filter((h) => h === day).map((h) => ({ day: h })), error: null },
      }),
    }),
  } as never;
}

const SUNDAY_8AM = new Date("2026-10-18T05:00:00Z");
const SUNDAY_2PM = new Date("2026-10-18T11:00:00Z");
const FRIDAY_8AM = new Date("2026-10-16T05:00:00Z");
const SUNDAY_3AM = new Date("2026-10-18T00:00:00Z");

beforeEach(() => {
  called = [];
  holidays = [];
  holidayError = null;
  summaryError = null;
  sendClaimed.mockClear();
  alertAdmins.mockClear();
});

describe("a working morning", () => {
  test("queues what is due, the summaries, and sends", async () => {
    const result = await sweep(fakeAdmin(), SUNDAY_8AM);

    expect(called).toEqual([
      "purge_trashed_tasks",
      "purge_old_errors",
      "enqueue_task_reminders",
      "enqueue_morning_summaries",
      "claim_reminders",
    ]);
    expect(result).toMatchObject({ quiet: null, summaries: 2, sent: 1 });
  });

  test("an afternoon run sends reminders but no morning summary", async () => {
    await sweep(fakeAdmin(), SUNDAY_2PM);
    expect(called).toContain("enqueue_task_reminders");
    expect(called).not.toContain("enqueue_morning_summaries");
  });

  test("before migration 37, the missing summary function is not an error", async () => {
    summaryError = { code: "PGRST202", message: "Could not find the function" };
    const log = vi.spyOn(console, "error").mockImplementation(() => {});

    const result = await sweep(fakeAdmin(), SUNDAY_8AM);

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
    const result = await sweep(fakeAdmin(), when);

    expect(result.quiet).toBe(why);
    expect(called).toEqual(["purge_trashed_tasks", "purge_old_errors"]);
    expect(sendClaimed).not.toHaveBeenCalled();
  });

  test("a company holiday is a day off", async () => {
    holidays = ["2026-10-18"];
    const result = await sweep(fakeAdmin(), SUNDAY_8AM);

    expect(result.quiet).toBe("holiday");
    expect(called).not.toContain("claim_reminders");
  });

  test("an unreadable holiday list does not hold back a working day", async () => {
    holidayError = { code: "PGRST205", message: "Could not find the table" };
    const result = await sweep(fakeAdmin(), SUNDAY_8AM);

    expect(result.quiet).toBeNull();
    expect(called).toContain("claim_reminders");
  });
});

describe("telling the admins about faults", () => {
  test("happens on a working morning, after the reminders", async () => {
    const result = await sweep(fakeAdmin(), SUNDAY_8AM);
    expect(alertAdmins).toHaveBeenCalledTimes(1);
    expect(result.alerted).toBe(1);
  });

  test("waits for the office to open, like everything else that reaches a person", async () => {
    await sweep(fakeAdmin(), FRIDAY_8AM);
    await sweep(fakeAdmin(), SUNDAY_3AM);
    expect(alertAdmins).not.toHaveBeenCalled();
  });

  test("is never the reason a run fails", async () => {
    alertAdmins.mockRejectedValueOnce(new Error("telegram down"));
    const errors = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const result = await sweep(fakeAdmin(), SUNDAY_8AM);
    expect(result).toMatchObject({ sent: 1, alerted: 0 });
    errors.mockRestore();
  });
});
