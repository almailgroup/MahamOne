/**
 * The private-message writes.
 *
 * Who may read, post to or delete from a conversation is decided by row-level
 * security and checked against a real Postgres in the migration — including
 * the part that matters most, that an admin sees none of it. What these cover
 * is the part the database cannot: refusing a message before the round trip,
 * telling a refusal apart from a success, and never letting the client name
 * the author.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

let inserted: Record<string, unknown> | null;
let updated: Record<string, unknown> | null;
let rpcCall: { name: string; args: Record<string, unknown> } | null;
/** How many rows the delete removed, which is how RLS reports a refusal. */
let deletedCount: number;
let dbError: { message: string } | null;
let rpcResult: unknown;

vi.mock("next/cache", () => ({ revalidatePath: () => {} }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { id: "me" } } }) },
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcCall = { name, args };
      return Promise.resolve({ data: rpcResult, error: dbError });
    },
    from: () => ({
      insert: (values: Record<string, unknown>) => {
        inserted = values;
        return {
          select: () => ({
            single: () =>
              Promise.resolve({
                error: dbError,
                data: dbError ? null : { id: "row-1", ...values },
              }),
          }),
        };
      },
      delete: () => ({
        eq: () => Promise.resolve({ error: dbError, count: deletedCount }),
      }),
      update: (values: Record<string, unknown>) => {
        updated = values;
        return {
          eq: () => ({ eq: () => Promise.resolve({ error: dbError }) }),
        };
      },
    }),
  }),
}));

const {
  startConversation,
  sendDirectMessage,
  deleteDirectMessage,
  markConversationRead,
} = await import("@/lib/data/dm-actions");

beforeEach(() => {
  inserted = null;
  updated = null;
  rpcCall = null;
  deletedCount = 1;
  dbError = null;
  rpcResult = "conversation-1";
});

describe("starting a conversation", () => {
  test("asks the database to find or open it, rather than inserting a row", async () => {
    expect(await startConversation("them")).toEqual({
      ok: true,
      data: "conversation-1",
    });
    // The function is the only way in: it decides who is in a conversation,
    // so a client cannot put itself in one it was not invited to.
    expect(rpcCall).toEqual({
      name: "start_direct_conversation",
      args: { other: "them" },
    });
  });

  test("refuses a conversation with yourself before asking", async () => {
    expect(await startConversation("me")).toEqual({
      ok: false,
      error: "dm.notYourself",
    });
    expect(rpcCall).toBeNull();
  });

  test("a database refusal is reported, not swallowed", async () => {
    dbError = { message: "that person is not on the team" };
    const outcome = await startConversation("ghost");
    expect(outcome.ok).toBe(false);
  });
});

describe("sending", () => {
  test("posts as whoever is signed in, never as whoever the caller names", async () => {
    const outcome = await sendDirectMessage("c1", "Are you free at three?");
    expect(outcome).toEqual({
      ok: true,
      data: {
        id: "row-1",
        conversation_id: "c1",
        author_id: "me",
        body: "Are you free at three?",
      },
    });
    expect(inserted).toMatchObject({ author_id: "me" });
  });

  test("trims, so a stray newline is not a message", async () => {
    await sendDirectMessage("c1", "  hello  \n");
    expect(inserted).toMatchObject({ body: "hello" });
  });

  test("refuses an empty message before the round trip", async () => {
    expect(await sendDirectMessage("c1", "   ")).toEqual({
      ok: false,
      error: "chat.emptyMessage",
    });
    expect(inserted).toBeNull();
  });

  test("refuses one longer than the column allows", async () => {
    expect(await sendDirectMessage("c1", "x".repeat(4001))).toEqual({
      ok: false,
      error: "chat.tooLong",
    });
    expect(inserted).toBeNull();
  });

  test("4000 exactly is allowed — the limit is inclusive, as in the check", async () => {
    const outcome = await sendDirectMessage("c1", "x".repeat(4000));
    expect(outcome.ok).toBe(true);
  });
});

describe("deleting", () => {
  test("removing your own message succeeds", async () => {
    expect(await deleteDirectMessage("m1")).toEqual({ ok: true, data: undefined });
  });

  test("a delete RLS filtered away is a refusal, not a success", async () => {
    // The database reports no error and no rows; without counting them the
    // UI would tell somebody their message was deleted when it was not.
    deletedCount = 0;
    expect(await deleteDirectMessage("not-mine")).toEqual({
      ok: false,
      error: "dm.notYours",
    });
  });
});

describe("marking read", () => {
  test("moves the marker to now", async () => {
    const before = Date.now();
    expect(await markConversationRead("c1")).toEqual({ ok: true, data: undefined });
    const at = Date.parse(String(updated?.last_read_at));
    expect(at).toBeGreaterThanOrEqual(before);
    expect(at).toBeLessThanOrEqual(Date.now());
  });
});
