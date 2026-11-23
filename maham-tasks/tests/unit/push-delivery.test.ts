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

/** The devices the server knows, which the provider looks the keys up in. */
let devices: { endpoint: string; p256dh: string; auth: string }[];
/** Endpoints the dispatcher asked the server to forget. */
let deleted: string[];

/**
 * The server's jobs, as the provider and the dispatcher both run them. Only
 * the two about devices answer anything; marking a reminder sent or failed,
 * and telling the person, just succeed.
 */
function fakeServer() {
  return {
    rpc: async (job: string, args: Record<string, unknown> = {}) => {
      if (job === "push_device") {
        // A list, empty when the device is gone.
        return {
          data: devices
            .filter((device) => device.endpoint === args.p_endpoint)
            .map(({ p256dh, auth }) => ({ p256dh, auth })),
          error: null,
        };
      }
      if (job === "forget_push_device") deleted.push(String(args.p_endpoint));
      return { data: null, error: null };
    },
  } as never;
}

vi.mock("@/lib/supabase/server-access", () => ({ createServerAccess: () => fakeServer() }));

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

describe("what the dispatcher does about it", () => {
  test("a gone device is removed rather than retried forever", async () => {
    failWith(410);
    const tally = await sendClaimed(fakeServer(), [push()]);

    expect(deleted).toEqual(["https://push.example/device-one"]);
    expect(tally.givenUp).toBe(1);
    expect(tally.retrying).toBe(0);
  });

  test("a device having a bad day is kept", async () => {
    failWith(503);
    await sendClaimed(fakeServer(), [push()]);

    expect(deleted).toEqual([]);
  });
});
