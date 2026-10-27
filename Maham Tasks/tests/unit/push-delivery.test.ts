/**
 * Sending to a device, and what to do when the device is gone.
 *
 * The push service answers 404 or 410 for a subscription that no longer
 * exists — the app was deleted, the browser data cleared, the permission
 * revoked. That is not a transient failure to retry for hours: it is a row
 * that should be removed, and these pin both halves of that.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

import type { DeliveryResult, QueuedReminder } from "@/lib/reminders/types";

/** What web-push does when the dispatcher calls it. */
let sending: (() => Promise<unknown>) | null = null;

vi.mock("web-push", () => ({
  default: {
    setVapidDetails: () => {},
    sendNotification: () => (sending ? sending() : Promise.resolve()),
    generateVAPIDKeys: () => ({ publicKey: "pub", privateKey: "priv" }),
  },
}));

vi.mock("@/lib/push/keys", () => ({
  vapidKeys: async () => ({ publicKey: "pub", privateKey: "priv" }),
  publicPushKey: async () => "pub",
  pushSubject: () => "https://portal.example",
}));

/** The device rows the provider looks the keys up in. */
let devices: { endpoint: string; p256dh: string; auth: string }[];
/** Endpoints the dispatcher deleted. */
let deleted: string[];

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () =>
    ({
      from: (table: string) => ({
        select: () => ({
          eq: (_column: string, endpoint: string) => ({
            maybeSingle: async () => ({
              data: devices.find((device) => device.endpoint === endpoint) ?? null,
              error: null,
            }),
          }),
        }),
        update: () => ({ eq: async () => ({ error: null }) }),
        delete: () => ({
          eq: async (_column: string, endpoint: string) => {
            if (table === "push_subscriptions") deleted.push(endpoint);
            return { error: null };
          },
        }),
      }),
      rpc: async () => ({ data: [], error: null }),
    }) as never,
}));

const { deliver } = await import("@/lib/reminders/providers");
const { sendClaimed } = await import("@/lib/reminders/dispatch");

const push = (over: Partial<QueuedReminder> = {}): QueuedReminder => ({
  id: "r1",
  user_id: "u1",
  task_id: "t1",
  channel: "push",
  kind: "due_soon",
  recipient: "https://push.example/device-one",
  subject: "Due soon: Sign the mandate",
  body: "Sign the mandate is due 21 Sep 13:00 UTC.",
  attempts: 0,
  ...over,
});

const failWith = (statusCode: number) => {
  sending = () => Promise.reject(Object.assign(new Error("push failed"), { statusCode }));
};

beforeEach(() => {
  sending = null;
  deleted = [];
  devices = [
    { endpoint: "https://push.example/device-one", p256dh: "k", auth: "a" },
  ];
});

describe("sending a push", () => {
  test("a known device is sent to", async () => {
    const result = await deliver(push());
    expect(result.ok).toBe(true);
  });

  test("a device with no row is gone, not retried", async () => {
    const result = (await deliver(
      push({ recipient: "https://push.example/never-registered" }),
    )) as Extract<DeliveryResult, { ok: false }>;

    expect(result.ok).toBe(false);
    expect(result.retryable).toBe(false);
    expect(result.gone).toBe(true);
  });

  test("410 from the push service is gone", async () => {
    failWith(410);
    const result = (await deliver(push())) as Extract<DeliveryResult, { ok: false }>;
    expect(result.gone).toBe(true);
    expect(result.retryable).toBe(false);
  });

  test("404 is gone too", async () => {
    failWith(404);
    const result = (await deliver(push())) as Extract<DeliveryResult, { ok: false }>;
    expect(result.gone).toBe(true);
  });

  test("a push service having a bad day is worth another try", async () => {
    failWith(503);
    const result = (await deliver(push())) as Extract<DeliveryResult, { ok: false }>;
    expect(result.retryable).toBe(true);
    expect(result.gone).toBeUndefined();
  });

  test("being told off for sending too fast is worth another try", async () => {
    failWith(429);
    const result = (await deliver(push())) as Extract<DeliveryResult, { ok: false }>;
    expect(result.retryable).toBe(true);
  });

  test("a rejected payload is not", async () => {
    failWith(400);
    const result = (await deliver(push())) as Extract<DeliveryResult, { ok: false }>;
    expect(result.retryable).toBe(false);
    expect(result.gone).toBeUndefined();
  });
});

/** The client the dispatcher writes the queue back through. */
const queueClient = () =>
  ({
    from: (table: string) => ({
      update: () => ({ eq: async () => ({ error: null }) }),
      delete: () => ({
        eq: async (_column: string, endpoint: string) => {
          if (table === "push_subscriptions") deleted.push(endpoint);
          return { error: null };
        },
      }),
    }),
    // Giving up on a reminder now also tells the person, through the
    // database function that writes the notification.
    rpc: async () => ({ data: null, error: null }),
  }) as never;

describe("what the dispatcher does about it", () => {
  test("a gone device is removed rather than retried forever", async () => {
    failWith(410);
    const tally = await sendClaimed(queueClient(), [push()]);

    expect(deleted).toEqual(["https://push.example/device-one"]);
    expect(tally.givenUp).toBe(1);
    expect(tally.retrying).toBe(0);
  });

  test("a device having a bad day is kept", async () => {
    failWith(503);
    await sendClaimed(queueClient(), [push()]);

    expect(deleted).toEqual([]);
  });
});
