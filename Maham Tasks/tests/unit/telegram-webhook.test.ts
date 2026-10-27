/**
 * The bot's webhook: who may add work, what is sent on, and what is said back.
 *
 * add_from_chat itself — task or My List, as whom — is checked against a real
 * Postgres in supabase/tests/telegram-quick-add.sql.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

let rpcCalls: { name: string; args: Record<string, unknown> }[];
let rpcAnswer: { data: unknown; error: { code?: string; message: string } | null };
let linkedChat: string | null;
let replies: string[];

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => ({
    rpc: async (name: string, args: Record<string, unknown>) => {
      rpcCalls.push({ name, args });
      return rpcAnswer;
    },
    from: (table: string) => {
      const chain = {
        select: () => chain,
        gte: () => chain,
        lte: async () => ({ data: [], error: null }),
        eq: (_column: string, value: string) => ({
          maybeSingle: async () => ({
            data: table === "notification_preferences" && value === linkedChat ? { user_id: "u1" } : null,
          }),
        }),
      };
      return chain;
    },
  }),
}));

const { POST } = await import("@/app/api/telegram/webhook/route");

const SECRET = "hook-secret";

function send(text: string, secret = SECRET) {
  return POST(
    new NextRequest("https://portal.test/api/telegram/webhook", {
      method: "POST",
      headers: { "x-telegram-bot-api-secret-token": secret, "content-type": "application/json" },
      body: JSON.stringify({ message: { text, chat: { id: 4242 } } }),
    }),
  );
}

beforeEach(() => {
  process.env.TELEGRAM_WEBHOOK_SECRET = SECRET;
  process.env.TELEGRAM_BOT_TOKEN = "bot-token";
  process.env.NEXT_PUBLIC_SITE_URL = "https://portal.test";
  rpcCalls = [];
  rpcAnswer = { data: { kind: "task", id: "t-1" }, error: null };
  linkedChat = "4242";
  replies = [];
  vi.stubGlobal("fetch", async (_url: string, init: { body: string }) => {
    replies.push(JSON.parse(init.body).text);
    return new Response("{}");
  });
});

afterEach(() => vi.unstubAllGlobals());

describe("adding work from the chat", () => {
  test("hands the parsed message to the database, for this chat only", async () => {
    await send("!Call the bank\nAbout the mandate");
    expect(rpcCalls).toEqual([
      {
        name: "add_from_chat",
        args: {
          chat: "4242",
          item_title: "Call the bank",
          item_detail: "About the mandate",
          item_priority: "high",
          due: null,
        },
      },
    ]);
    expect(replies[0]).toBe("Added to your tasks: Call the bank\nhttps://portal.test/tasks?filter=all&task=t-1");
  });

  test("says when it went to My List instead", async () => {
    rpcAnswer = { data: { kind: "note", id: "n-1" }, error: null };
    await send("Buy stamps");
    expect(replies[0]).toBe("Added to My List: Buy stamps\nhttps://portal.test/my-list");
  });

  test("a chat nobody linked is told how to link it, and nothing is added", async () => {
    rpcAnswer = { data: null, error: null };
    await send("Buy stamps");
    expect(replies[0]).toMatch(/send me the code it shows/);
  });

  test("before migration 42 it says so, rather than failing quietly", async () => {
    rpcAnswer = { data: null, error: { code: "PGRST202", message: "Could not find the function" } };
    await send("Buy stamps");
    expect(replies[0]).toMatch(/not switched on yet/);
  });

  test("a command is answered with help, not added", async () => {
    await send("/help");
    expect(rpcCalls).toEqual([]);
    expect(replies[0]).toMatch(/Send me anything to add it/);
  });

  test("nothing at all without the webhook's secret", async () => {
    const response = await send("Buy stamps", "wrong");
    expect(response.status).toBe(404);
    expect(rpcCalls).toEqual([]);
    expect(replies).toEqual([]);
  });
});
