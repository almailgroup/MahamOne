/**
 * Adding a teammate — the only way an account is made.
 *
 * The database refuses an account that does not name the admin who added it
 * in app_metadata (close_self_registration, proven against Postgres in
 * supabase/tests/self-registration.sql). These cover this side of that
 * agreement: the account created here names the admin who asked, and nobody
 * but an admin gets as far as creating one.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";

const ADMIN = "00000000-0000-4000-8000-000000000001";

let callerRole: string;
/** How the caller signed in: "aal2" after the authenticator app's code. */
let callerAal: string;
let createUser: ReturnType<typeof vi.fn>;
let deleteFactor: ReturnType<typeof vi.fn>;
/** The authenticator apps the teammate has. */
let factors: { id: string }[];

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
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { role: callerRole } }) }),
      }),
      update: () => ({ eq: async () => ({ error: null }) }),
    }),
  }),
}));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => ({
    auth: {
      admin: {
        createUser,
        mfa: {
          listFactors: async () => ({ data: { factors }, error: null }),
          deleteFactor: (params: unknown) => deleteFactor(params),
        },
      },
    },
  }),
}));

const { addTeamMember, removeMemberTwoStep } = await import("@/lib/data/team-actions");

function form(fields: Record<string, string>) {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

const newHire = { fullName: "Lina Aboud", email: "lina@almailgroup.com", role: "member" };

beforeEach(() => {
  callerRole = "admin";
  callerAal = "aal2";
  createUser = vi.fn(async () => ({ data: { user: { id: "new-1" } }, error: null }));
  deleteFactor = vi.fn(async () => ({ data: null, error: null }));
  factors = [];
});

describe("addTeamMember", () => {
  test("the account names the admin who added it, where only the server can write", async () => {
    const outcome = await addTeamMember(null, form(newHire));
    expect(outcome.ok).toBe(true);
    expect(createUser).toHaveBeenCalledTimes(1);
    expect(createUser.mock.calls[0][0]).toMatchObject({
      email: "lina@almailgroup.com",
      email_confirm: true,
      app_metadata: { added_by: ADMIN },
    });
    // Not in user_metadata, which the person themselves can edit — the
    // database would not accept it from there.
    expect(createUser.mock.calls[0][0].user_metadata).not.toHaveProperty("added_by");
  });

  test("somebody who is not an admin never gets as far as creating an account", async () => {
    callerRole = "manager";
    const outcome = await addTeamMember(null, form(newHire));
    expect(outcome).toEqual({ ok: false, error: "action.adminOnly" });
    expect(createUser).not.toHaveBeenCalled();
  });

  test("an admin who signed in with the password alone is sent to set up two-step first", async () => {
    callerAal = "aal1";
    const outcome = await addTeamMember(null, form(newHire));
    expect(outcome).toEqual({ ok: false, error: "action.needsTwoStep" });
    expect(createUser).not.toHaveBeenCalled();
  });
});

describe("removeMemberTwoStep", () => {
  const LINA = "00000000-0000-4000-8000-000000000006";

  test("takes away every app the teammate had, for a lost phone", async () => {
    factors = [{ id: "f1" }, { id: "f2" }];
    const outcome = await removeMemberTwoStep(LINA);
    expect(outcome).toEqual({ ok: true, data: { removed: 2 } });
    expect(deleteFactor.mock.calls.map(([params]) => params)).toEqual([
      { id: "f1", userId: LINA },
      { id: "f2", userId: LINA },
    ]);
  });

  test("only an admin who has signed in with their own app", async () => {
    factors = [{ id: "f1" }];
    callerAal = "aal1";
    expect(await removeMemberTwoStep(LINA)).toEqual({ ok: false, error: "action.needsTwoStep" });
    callerRole = "manager";
    callerAal = "aal2";
    expect(await removeMemberTwoStep(LINA)).toEqual({ ok: false, error: "action.adminOnly" });
    expect(deleteFactor).not.toHaveBeenCalled();
  });

  test("not on their own account, which is turned off from Profile with a code", async () => {
    factors = [{ id: "f1" }];
    expect(await removeMemberTwoStep(ADMIN)).toEqual({
      ok: false,
      error: "action.ownTwoStepFromProfile",
    });
    expect(deleteFactor).not.toHaveBeenCalled();
  });
});
