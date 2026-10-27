import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { alertAdmins, alertText } = await import("@/lib/reminders/admin-alerts");
import type { AlertDigest } from "@/lib/reminders/admin-alerts";

const digest = (over: Partial<AlertDigest> = {}): AlertDigest => ({
  since: "2026-10-18T05:00:00Z",
  faults: 3,
  pages: [
    { source: "browser", page: "/tasks", count: 2 },
    { source: "server", page: "/calendar", count: 1 },
  ],
  failedReminders: 1,
  recipients: ["4501", "4502"],
  ...over,
});

describe("the note to the admins", () => {
  test("says how many, where, and links to the details", () => {
    const text = alertText(digest(), "https://portal.example");
    expect(text).toContain("since Sun 08:00");
    expect(text).toContain("3 faults:");
    expect(text).toContain("• /tasks — 2 in the browser");
    expect(text).toContain("• /calendar — 1 on the server");
    expect(text).toContain("1 reminder could not be delivered.");
    expect(text).toContain("أعطال: 3");
    expect(text).toMatch(/https:\/\/portal\.example\/profile#reminders$/);
  });

  test("is not sent when there is nothing new", () => {
    expect(alertText(digest({ faults: 0, pages: [], failedReminders: 0 }), "")).toBeNull();
  });
});

describe("sending it", () => {
  let inserted: unknown[];
  let fetches: { url: string; body: { chat_id: string } }[];
  let answer: AlertDigest | null;

  const fakeAdmin = () =>
    ({
      rpc: async (name: string) => {
        expect(name).toBe("admin_alert_digest");
        return { data: answer, error: null };
      },
      from: (table: string) => ({
        insert: async (row: unknown) => {
          expect(table).toBe("admin_alerts");
          inserted.push(row);
          return { error: null };
        },
      }),
    }) as never;

  beforeEach(() => {
    inserted = [];
    fetches = [];
    answer = digest();
    vi.stubEnv("TELEGRAM_BOT_TOKEN", "token");
    vi.stubGlobal("fetch", async (url: string, init: { body: string }) => {
      const body = JSON.parse(init.body);
      fetches.push({ url, body });
      // The second admin's chat has gone away.
      return { ok: body.chat_id !== "4502" } as Response;
    });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  test("goes to each admin on Telegram, and is recorded once it reached one", async () => {
    const now = new Date("2026-10-18T06:00:00Z");
    expect(await alertAdmins(fakeAdmin(), now)).toBe(1);
    expect(fetches.map((f) => f.body.chat_id)).toEqual(["4501", "4502"]);
    expect(inserted).toEqual([{ sent_at: now.toISOString(), faults: 3, failures: 1, reached: 1 }]);
  });

  test("is not recorded when it reached nobody, so the next run tries again", async () => {
    vi.stubGlobal("fetch", async () => ({ ok: false }) as Response);
    expect(await alertAdmins(fakeAdmin())).toBe(0);
    expect(inserted).toEqual([]);
  });

  test("does nothing without a bot, or with nothing to say", async () => {
    answer = digest({ faults: 0, pages: [], failedReminders: 0 });
    expect(await alertAdmins(fakeAdmin())).toBe(0);
    vi.stubEnv("TELEGRAM_BOT_TOKEN", "");
    answer = digest();
    expect(await alertAdmins(fakeAdmin())).toBe(0);
    expect(fetches).toEqual([]);
  });
});
