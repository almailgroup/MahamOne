/**
 * The bot's webhook: linking a chat, who may add work, what is sent on, and
 * what is said back.
 *
 * add_from_chat itself — task or My List, as whom — is checked against a real
 * Postgres in supabase/tests/telegram-quick-add.sql.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

/** Every one of the server's jobs the webhook ran, in order. */
let rpcCalls: { name: string; args: Record<string, unknown> }[];
/** What add_from_chat answers. */
let rpcAnswer: { data: unknown; error: { code?: string; message: string } | null };
/** The chat somebody has linked, if any. */
let linkedChat: string | null;
/** The linking code that is still waiting to be used. */
let freshCode: string;
let replies: string[];

vi.mock("@/lib/supabase/server-access", () => ({
  createServerAccess: () => ({
    rpc: async (name: string, args: Record<string, unknown> = {}) => {
      rpcCalls.push({ name, args });
      switch (name) {
        case "holidays":
          return { data: [], error: null };
        case "telegram_linked":
          return { data: args.p_chat === linkedChat, error: null };
        case "link_telegram":
          // False for a code that was made up or has been used already.
          return { data: args.p_code === freshCode, error: null };
        default:
          return rpcAnswer;
      }
    },
  }),
}));

const { POST } = await import("@/app/api/telegram/webhook/route");

/** Only the calls to one job. */
const callsTo = (name: string) => rpcCalls.filter((call) => call.name === name);

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
  freshCode = "K7Q2M9XP";
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
    expect(callsTo("add_from_chat")).toEqual([
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
    expect(callsTo("add_from_chat")).toEqual([]);
    expect(replies[0]).toMatch(/Send me anything to add it/);
  });

  test("a command from a chat nobody linked is told how to link it first", async () => {
    linkedChat = null;
    await send("/help");
    expect(callsTo("telegram_linked")).toEqual([
      { name: "telegram_linked", args: { p_chat: "4242" } },
    ]);
    expect(replies[0]).toMatch(/send me the code it shows/);
  });

  test("nothing at all without the webhook's secret", async () => {
    const response = await send("Buy stamps", "wrong");
    expect(response.status).toBe(404);
    expect(rpcCalls).toEqual([]);
    expect(replies).toEqual([]);
  });
});

describe("linking a chat", () => {
  test("a fresh code from the profile links this chat", async () => {
    linkedChat = null;
    await send(`/start ${freshCode}`);
    expect(callsTo("link_telegram")).toEqual([
      { name: "link_telegram", args: { p_code: "K7Q2M9XP", p_chat: "4242" } },
    ]);
    expect(replies[0]).toMatch(/^Linked\. You will get your task reminders here\./);
    // Linking adds nothing.
    expect(callsTo("add_from_chat")).toEqual([]);
  });

  test("a code that was made up, or used already, is refused", async () => {
    await send("/start ZZ99ZZ99");
    expect(replies).toEqual(["That code is not valid or has already been used."]);
  });
});
