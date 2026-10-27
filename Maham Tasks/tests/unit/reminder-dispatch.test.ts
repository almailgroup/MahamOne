/**
 * The half of the dispatcher that both callers share.
 *
 * The daily sweep claims a batch of everybody's due reminders; the assignment
 * path claims one task's. What happens to a claimed row after that — sent,
 * retried with a backoff, or given up on — is the same code, and this is what
 * makes it the same code rather than two copies that drift.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

import type { DeliveryResult, QueuedReminder } from "@/lib/reminders/types";

const deliver = vi.fn<(r: QueuedReminder) => Promise<DeliveryResult>>();
vi.mock("@/lib/reminders/providers", () => ({ deliver: (r: QueuedReminder) => deliver(r) }));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => fakeAdmin() }));

/** Every update the dispatcher wrote back, by reminder id. */
let writes: Record<string, Record<string, unknown>>;
/** What `claim_task_reminders` should hand back. */
let claimable: QueuedReminder[];
/** Reminder ids the dispatcher told somebody about. */
let told: string[];
let claimError: string | null;

function fakeAdmin() {
  return {
    from: (table: string) => ({
      update: (values: Record<string, unknown>) => ({
        eq: (_column: string, id: string) => {
          if (table === "reminder_queue") writes[id] = values;
          return Promise.resolve({ error: null });
        },
      }),
    }),
    rpc: async (name: string, args: Record<string, unknown>) => {
      // Telling somebody their reminder could not be delivered goes through
      // the database, like every other notification here.
      if (name === "notify_reminder_failed") {
        told.push(String(args.reminder));
        return { data: null, error: null };
      }
      return claimError
        ? { data: null, error: { message: claimError } }
        : { data: claimable, error: null };
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

beforeEach(() => {
  writes = {};
  told = [];
  claimable = [];
  claimError = null;
  deliver.mockReset();
});

describe("sendClaimed", () => {
  test("a delivered reminder is marked sent and its claim released", async () => {
    deliver.mockResolvedValue({ ok: true });
    const tally = await sendClaimed(fakeAdmin(), [reminder()]);

    expect(tally).toMatchObject({ considered: 1, sent: 1, retrying: 0, givenUp: 0 });
    expect(writes.r1).toMatchObject({ status: "sent", attempts: 1, last_error: null, claimed_at: null });
  });

  /**
   * The claim has to come off whatever happens. A row left in 'sending' is
   * invisible to the next run until the ten-minute rescue, which turns a
   * moment's provider trouble into a reminder that arrives very late.
   */
  test("a transient failure goes back to pending, backed off, unclaimed", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Telegram 429", retryable: true });
    const before = Date.now();
    const tally = await sendClaimed(fakeAdmin(), [reminder()]);

    expect(tally).toMatchObject({ sent: 0, retrying: 1, givenUp: 0 });
    expect(writes.r1).toMatchObject({ status: "pending", attempts: 1, claimed_at: null });
    expect(writes.r1.last_error).toBe("Telegram 429");
    // Backed off rather than retried immediately.
    expect(new Date(writes.r1.scheduled_for as string).getTime()).toBeGreaterThan(before);
  });

  test("a permanent failure is not retried at all", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 403", retryable: false });
    const tally = await sendClaimed(fakeAdmin(), [reminder()]);

    expect(tally).toMatchObject({ sent: 0, retrying: 0, givenUp: 1 });
    expect(writes.r1).toMatchObject({ status: "failed", attempts: 1 });
    // No new schedule: there is nothing to come back for.
    expect(writes.r1.scheduled_for).toBeUndefined();
  });

  test("a transient failure is given up on once the attempts run out", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Telegram 502", retryable: true });
    const tally = await sendClaimed(fakeAdmin(), [reminder({ attempts: MAX_ATTEMPTS - 1 })]);

    expect(tally).toMatchObject({ givenUp: 1, retrying: 0 });
    expect(writes.r1).toMatchObject({ status: "failed", attempts: MAX_ATTEMPTS });
  });

  test("one bad reminder does not stop the rest of the batch", async () => {
    deliver
      .mockResolvedValueOnce({ ok: false, error: "no", retryable: false })
      .mockResolvedValue({ ok: true });

    const tally = await sendClaimed(fakeAdmin(), [
      reminder({ id: "r1" }),
      reminder({ id: "r2" }),
      reminder({ id: "r3" }),
    ]);

    expect(tally).toMatchObject({ considered: 3, sent: 2, givenUp: 1 });
    expect(writes.r2).toMatchObject({ status: "sent" });
    expect(writes.r3).toMatchObject({ status: "sent" });
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

    const tally = await sendClaimed(fakeAdmin(), [reminder({ id: "r9" })]);

    expect(tally.givenUp).toBe(1);
    expect(told).toEqual(["r9"]);
  });

  test("a reminder that will be tried again tells nobody yet", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 503", retryable: true });

    await sendClaimed(fakeAdmin(), [reminder({ id: "r9", attempts: 0 })]);

    expect(told).toEqual([]);
  });

  test("the row records when it gave up, not when it was queued", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Twilio 400", retryable: false });

    await sendClaimed(fakeAdmin(), [reminder({ id: "r9" })]);

    expect(writes.r9.status).toBe("failed");
    expect(typeof writes.r9.failed_at).toBe("string");
  });

  test("and clears that mark while it is still being tried", async () => {
    deliver.mockResolvedValue({ ok: false, error: "Resend 503", retryable: true });

    await sendClaimed(fakeAdmin(), [reminder({ id: "r9" })]);

    expect(writes.r9.status).toBe("pending");
    expect(writes.r9.failed_at).toBeNull();
  });
});
