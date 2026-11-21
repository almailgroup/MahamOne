/**
 * The half of the dispatcher that both callers share.
 *
 * The daily sweep claims a batch of everybody's due reminders; the assignment
 * path claims one task's. What happens to a claimed row after that — sent,
 * retried with a backoff, or given up on — is the same code, and this is what
 * makes it the same code rather than two copies that drift.
 *
 * The queue is written back through the server's own jobs (reminder_sent,
 * reminder_failed), which release the claim and stamp the times themselves;
 * these check what the dispatcher tells them.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

import type { DeliveryResult, QueuedReminder } from "@/lib/reminders/types";

const deliver = vi.fn<(r: QueuedReminder) => Promise<DeliveryResult>>();
vi.mock("@/lib/reminders/providers", () => ({ deliver: (r: QueuedReminder) => deliver(r) }));
vi.mock("@/lib/supabase/server-access", () => ({ createServerAccess: () => fakeServer() }));

/** The last thing the dispatcher wrote back about each reminder, by its id. */
let writes: Record<string, { job: string; args: Record<string, unknown> }>;
/** What `claim_task_reminders` should hand back. */
let claimable: QueuedReminder[];
/** Reminder ids the dispatcher told somebody about. */
let told: string[];
let claimError: string | null;

function fakeServer() {
  return {
    rpc: async (job: string, args: Record<string, unknown> = {}) => {
      if (job === "claim_task_reminders") {
        return claimError
          ? { data: null, error: { message: claimError } }
          : { data: claimable, error: null };
      }
      // Telling somebody their reminder could not be delivered goes through
      // the database, like every other notification here.
      if (job === "notify_reminder_failed") {
        told.push(String(args.reminder));
        return { data: null, error: null };
      }
      if (job === "reminder_sent" || job === "reminder_failed") {
        writes[String(args.p_id)] = { job, args };
      }
      return { data: null, error: null };
    },
  } as never;
}

const { sendClaimed, dispatchForTask, MAX_ATTEMPTS } = await import(
  "@/lib/reminders/dispatch"
);

const reminder = (over: Partial<QueuedReminder> = {}): QueuedReminder => ({
  id: "r1",
  user_id: "u1",
  task_id: "t1",
  channel: "telegram",
  kind: "assigned",
  recipient: "12345",
  subject: null,
  body: "You were assigned something",
  attempts: 0,
  ...over,
});

const FIFTEEN_MINUTES = 15 * 60_000;

beforeEach(() => {
  writes = {};
  told = [];
  claimable = [];
  claimError = null;
  deliver.mockReset();
});

describe("sendClaimed", () => {
  test("a delivered reminder is marked sent, which also releases its claim", async () => {
    deliver.mockResolvedValue({ ok: true });
    const tally = await sendClaimed(fakeServer(), [reminder()]);

    expect(tally).toMatchObject({ considered: 1, sent: 1, retrying: 0, givenUp: 0 });
    expect(writes.r1).toEqual({ job: "reminder_sent", args: { p_id: "r1", p_attempts: 1 } });
  });

  /**
   * The claim has to come off whatever happens. A row left in 'sending' is
   * invisible to the next run until the ten-minute rescue, which turns a
   * moment's provider trouble into a reminder that arrives very late.
   * reminder_failed releases it; what matters here is that it is asked to
   * retry, and not straight away.
   */
  test("a transient failure goes back to be retried, backed off", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Telegram 429", retryable: true });
    const before = Date.now();
    const tally = await sendClaimed(fakeServer(), [reminder()]);
    const after = Date.now();

    expect(tally).toMatchObject({ sent: 0, retrying: 1, givenUp: 0 });
    expect(writes.r1.job).toBe("reminder_failed");
    expect(writes.r1.args).toMatchObject({
      p_id: "r1",
      p_attempts: 1,
      p_error: "Telegram 429",
      p_exhausted: false,
    });
    // Backed off by a quarter of an hour rather than retried immediately.
    const retryAt = new Date(writes.r1.args.p_retry_at as string).getTime();
    expect(retryAt).toBeGreaterThanOrEqual(before + FIFTEEN_MINUTES);
    expect(retryAt).toBeLessThanOrEqual(after + FIFTEEN_MINUTES);
  });

  test("each attempt waits longer than the one before", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 503", retryable: true });
    const before = Date.now();
    await sendClaimed(fakeServer(), [reminder({ attempts: 1 })]);

    // The second attempt failed: half an hour before the third.
    const retryAt = new Date(writes.r1.args.p_retry_at as string).getTime();
    expect(retryAt).toBeGreaterThanOrEqual(before + 2 * FIFTEEN_MINUTES);
  });

  test("a permanent failure is not retried at all", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 403", retryable: false });
    const tally = await sendClaimed(fakeServer(), [reminder()]);

    expect(tally).toMatchObject({ sent: 0, retrying: 0, givenUp: 1 });
    // No new time: there is nothing to come back for.
    expect(writes.r1).toEqual({
      job: "reminder_failed",
      args: {
        p_id: "r1",
        p_attempts: 1,
        p_error: "Resend 403",
        p_exhausted: true,
        p_retry_at: null,
      },
    });
  });

  test("a transient failure is given up on once the attempts run out", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Telegram 502", retryable: true });
    const tally = await sendClaimed(fakeServer(), [reminder({ attempts: MAX_ATTEMPTS - 1 })]);

    expect(tally).toMatchObject({ givenUp: 1, retrying: 0 });
    expect(writes.r1.args).toMatchObject({
      p_attempts: MAX_ATTEMPTS,
      p_exhausted: true,
      p_retry_at: null,
    });
  });

  test("one bad reminder does not stop the rest of the batch", async () => {
    deliver
      .mockResolvedValueOnce({ ok: false, error: "no", retryable: false })
      .mockResolvedValue({ ok: true });

    const tally = await sendClaimed(fakeServer(), [
      reminder({ id: "r1" }),
      reminder({ id: "r2" }),
      reminder({ id: "r3" }),
    ]);

    expect(tally).toMatchObject({ considered: 3, sent: 2, givenUp: 1 });
    expect(writes.r1.job).toBe("reminder_failed");
    expect(writes.r2.job).toBe("reminder_sent");
    expect(writes.r3.job).toBe("reminder_sent");
  });
});

describe("dispatchForTask", () => {
  test("sends what the task has waiting", async () => {
    claimable = [reminder({ id: "a" }), reminder({ id: "b", channel: "email" })];
    deliver.mockResolvedValue({ ok: true });

    expect(await dispatchForTask("t1")).toMatchObject({ considered: 2, sent: 2 });
    expect(deliver).toHaveBeenCalledTimes(2);
  });

  test("a task with nothing queued sends nothing", async () => {
    claimable = [];
    expect(await dispatchForTask("t1")).toBeNull();
    expect(deliver).not.toHaveBeenCalled();
  });

  /**
   * This is called from a Server Action once the assignment is already saved.
   * Throwing here would turn a successful assignment into a failed one over a
   * provider the person assigning has nothing to do with.
   */
  test("a broken queue is swallowed, not thrown", async () => {
    claimError = "connection refused";
    await expect(dispatchForTask("t1")).resolves.toBeNull();
  });

  test("a provider that throws is swallowed too", async () => {
    claimable = [reminder()];
    deliver.mockRejectedValue(new Error("socket hang up"));
    await expect(dispatchForTask("t1")).resolves.toBeNull();
  });
});

describe("when a reminder cannot be delivered at all", () => {
  test("the person is told, once, after the last attempt", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Twilio 400", retryable: false });

    const tally = await sendClaimed(fakeServer(), [reminder({ id: "r9" })]);

    expect(tally.givenUp).toBe(1);
    expect(told).toEqual(["r9"]);
  });

  test("a reminder that will be tried again tells nobody yet", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 503", retryable: true });

    await sendClaimed(fakeServer(), [reminder({ id: "r9", attempts: 0 })]);

    expect(told).toEqual([]);
  });

  /**
   * The database stamps failed_at when it is told the reminder was given up
   * on, so the row says when it gave up, not when it was queued: an hour of
   * retries can sit between the two.
   */
  test("the row is marked as given up, so it records when", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Twilio 400", retryable: false });

    await sendClaimed(fakeServer(), [reminder({ id: "r9" })]);

    expect(writes.r9.job).toBe("reminder_failed");
    expect(writes.r9.args.p_exhausted).toBe(true);
  });

  test("and not while it is still being tried", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 503", retryable: true });

    await sendClaimed(fakeServer(), [reminder({ id: "r9" })]);

    expect(writes.r9.job).toBe("reminder_failed");
    expect(writes.r9.args.p_exhausted).toBe(false);
    expect(typeof writes.r9.args.p_retry_at).toBe("string");
  });
});
