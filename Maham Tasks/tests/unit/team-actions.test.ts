/**
 * Adding a teammate, taking back an invite, and the one thing an admin may
 * still undo on somebody else's sign-in.
 *
 * Maham Tasks shares its accounts with Maham One, so nothing here holds a
 * service key, signs anybody up or sets a password. An admin's own session
 * invites by email (tasks.add_teammate); the person joins by signing in here
 * themselves (tasks.join). These cover this side of that: what each answer
 * from the database becomes, and that nobody but an admin who signed in with
 * two steps gets as far as asking.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

const ADMIN = "00000000-0000-4000-8000-000000000001";

let callerRole: string;
/** How the caller signed in: "aal2" after the authenticator app's code. */
let callerAal: string;
/** What tasks.add_teammate says it did. */
let teammateStatus: "already" | "invited";
/** How many authenticator apps tasks.remove_two_step took away. */
let removedCount: number;
/** The database functions the admin's session called, in order. */
let rpcCalls: { name: string; args: Record<string, unknown> }[];
/** The invites deleted, by email. */
let deletedInvites: string[];

vi.mock("next/cache", () => ({ revalidatePath: () => {} }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: ADMIN } } }),
      getSession: async () => ({
        data: {
          session: {
            access_token: `e30.${Buffer.from(JSON.stringify({ aal: callerAal })).toString("base64url")}.sig`,
          },
        },
      }),
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { role: callerRole } }) }),
      }),
      delete: () => ({
        eq: async (_column: string, value: string) => {
          if (table === "invites") deletedInvites.push(value);
          return { error: null };
        },
      }),
    }),
    rpc: async (name: string, args: Record<string, unknown>) => {
      rpcCalls.push({ name, args });
      if (name === "add_teammate") return { data: { status: teammateStatus }, error: null };
      if (name === "remove_two_step") return { data: removedCount, error: null };
      return { data: null, error: { message: `unexpected ${name}` } };
    },
  }),
}));

const { addTeamMember, removeMemberTwoStep, withdrawInvite } = await import(
  "@/lib/data/team-actions"
);

function form(fields: Record<string, string>) {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

const newHire = { fullName: "Noor Example", email: "new.hire@example.com", role: "member" };

beforeEach(() => {
  callerRole = "admin";
  callerAal = "aal2";
  teammateStatus = "invited";
  removedCount = 0;
  rpcCalls = [];
  deletedInvites = [];
});

describe("addTeamMember", () => {
  test("invites the email, as the admin asked", async () => {
    const outcome = await addTeamMember(null, form(newHire));

    expect(outcome).toEqual({
      ok: true,
      data: { status: "invited", email: "new.hire@example.com" },
    });
    expect(rpcCalls).toEqual([
      {
        name: "add_teammate",
        args: { p_email: "new.hire@example.com", p_full_name: "Noor Example", p_role: "member" },
      },
    ]);
  });

  test("somebody already on the team is said to be", async () => {
    teammateStatus = "already";
    const outcome = await addTeamMember(null, form(newHire));

    expect(outcome).toEqual({
      ok: true,
      data: { status: "already", email: "new.hire@example.com" },
    });
  });

  test("a form that doesn't add up never reaches the database", async () => {
    const outcome = await addTeamMember(null, form({ ...newHire, email: "not-an-email" }));

    expect(outcome.ok).toBe(false);
    expect(rpcCalls).toEqual([]);
  });

  test("somebody who is not an admin never gets as far as asking", async () => {
    callerRole = "manager";
    const outcome = await addTeamMember(null, form(newHire));

    expect(outcome).toEqual({ ok: false, error: "action.adminOnly" });
    expect(rpcCalls).toEqual([]);
  });

  test("an admin who signed in with the password alone is sent to set up two-step first", async () => {
    callerAal = "aal1";
    const outcome = await addTeamMember(null, form(newHire));

    expect(outcome).toEqual({ ok: false, error: "action.needsTwoStep" });
    expect(rpcCalls).toEqual([]);
  });
});

describe("withdrawInvite", () => {
  test("takes back the invite for that email", async () => {
    expect(await withdrawInvite("new.hire@example.com")).toEqual({ ok: true, data: undefined });
    expect(deletedInvites).toEqual(["new.hire@example.com"]);
  });

  test("only for an admin signed in with two steps, and only for an email", async () => {
    callerAal = "aal1";
    expect(await withdrawInvite("new.hire@example.com")).toEqual({
      ok: false,
      error: "action.needsTwoStep",
    });
    callerRole = "manager";
    callerAal = "aal2";
    expect(await withdrawInvite("new.hire@example.com")).toEqual({
      ok: false,
      error: "action.adminOnly",
    });
    callerRole = "admin";
    expect((await withdrawInvite("nobody")).ok).toBe(false);
    expect(deletedInvites).toEqual([]);
  });
});

describe("removeMemberTwoStep", () => {
  const MEMBER = "00000000-0000-4000-8000-000000000006";

  test("takes away the teammate's authenticator app, for a lost phone", async () => {
    removedCount = 1;
    const outcome = await removeMemberTwoStep(MEMBER);

    expect(outcome).toEqual({ ok: true, data: { removed: 1 } });
    expect(rpcCalls).toEqual([{ name: "remove_two_step", args: { p_user: MEMBER } }]);
  });

  test("only an admin who has signed in with their own app", async () => {
    callerAal = "aal1";
    expect(await removeMemberTwoStep(MEMBER)).toEqual({ ok: false, error: "action.needsTwoStep" });
    callerRole = "manager";
    callerAal = "aal2";
    expect(await removeMemberTwoStep(MEMBER)).toEqual({ ok: false, error: "action.adminOnly" });
    expect(rpcCalls).toEqual([]);
  });

  test("not on their own account, which is turned off from Profile with a code", async () => {
    expect(await removeMemberTwoStep(ADMIN)).toEqual({
      ok: false,
      error: "action.ownTwoStepFromProfile",
    });
    expect(rpcCalls).toEqual([]);
  });
});
