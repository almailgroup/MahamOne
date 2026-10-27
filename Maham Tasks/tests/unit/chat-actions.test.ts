/**
 * The team room's two writes.
 *
 * What may be written is decided by row-level security, not here — the insert
 * policy requires `author_id = auth.uid()` and the delete policy allows an
 * author or an admin, and both are checked against a real Postgres in the
 * migration. What these cover is the part the database cannot: refusing a
 * message before the round trip, and telling the difference between a delete
 * that was not allowed and one that worked.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

let inserted: Record<string, unknown> | null;
/** How many rows the delete removed, which is how RLS reports a refusal. */
let deletedCount: number;
let dbError: { message: string } | null;

vi.mock("next/cache", () => ({ revalidatePath: () => {} }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { id: "me" } } }) },
    from: () => ({
      insert: (values: Record<string, unknown>) => {
        inserted = values;
        // The action reads the saved row back so the sender sees it at once.
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
    }),
  }),
}));

const { sendTeamMessage, deleteTeamMessage } = await import(
  "@/lib/data/chat-actions"
);

beforeEach(() => {
  inserted = null;
  deletedCount = 1;
  dbError = null;
});

describe("sendTeamMessage", () => {
  test("posts the message as whoever is signed in", async () => {
    expect(await sendTeamMessage("The meeting moved to 3pm")).toEqual({
      ok: true,
      data: { id: "row-1", author_id: "me", body: "The meeting moved to 3pm" },
    });
    // Never from the caller: the insert policy would refuse any other id, and
    // this is what keeps the two in step.
    expect(inserted).toEqual({ author_id: "me", body: "The meeting moved to 3pm" });
  });

  test("trims before sending, so a stray newline is not a message", async () => {
    await sendTeamMessage("  hello  \n");
    expect(inserted).toMatchObject({ body: "hello" });
  });

  test("nothing but whitespace never reaches the database", async () => {
    expect(await sendTeamMessage("   \n  ")).toEqual({
      ok: false,
      error: "chat.emptyMessage",
    });
    expect(inserted).toBeNull();
  });

  /**
   * The same 4000 the table's own check enforces. Refusing here saves a round
   * trip and gives a sentence back instead of a constraint violation.
   */
  test("an over-long message is refused before the round trip", async () => {
    expect(await sendTeamMessage("x".repeat(4001))).toEqual({
      ok: false,
      error: "chat.tooLong",
    });
    expect(inserted).toBeNull();
    expect((await sendTeamMessage("x".repeat(4000))).ok).toBe(true);
  });
});

describe("deleteTeamMessage", () => {
  test("a delete that removed a row succeeded", async () => {
    deletedCount = 1;
    expect(await deleteTeamMessage("m1")).toEqual({ ok: true, data: undefined });
  });

  /**
   * Row-level security filters rather than refuses: deleting somebody else's
   * message removes nothing and reports no error at all. Without counting the
   * rows this looked exactly like success, and the message stayed on screen
   * having apparently been deleted.
   */
  test("a delete that removed nothing is reported, not swallowed", async () => {
    deletedCount = 0;
    expect(await deleteTeamMessage("someone-elses")).toEqual({
      ok: false,
      error: "chat.notYours",
    });
  });
});
