/**
 * Two-step sign-in, from the middleware's side: who is sent to the code page,
 * and who is let through.
 *
 * What a half-signed-in session may do in the database is checked against a
 * real Postgres in supabase/tests/two-step.sql.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

import { qrSource, safeNext, secondStepPending, tokenAal } from "@/lib/supabase/second-step";

/** A token with these claims; the signature is never checked here. */
const token = (claims: Record<string, unknown>) =>
  `e30.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.sig`;

const withApp = { factors: [{ status: "verified" }] };
const halfSetUp = { factors: [{ status: "unverified" }] };

describe("reading the token", () => {
  test("finds the aal claim", () => {
    expect(tokenAal(token({ aal: "aal2" }))).toBe("aal2");
    expect(tokenAal(token({ aal: "aal1", email: "ليلى@example.test" }))).toBe("aal1");
  });

  test("anything else is no claim at all", () => {
    expect(tokenAal(token({}))).toBeNull();
    expect(tokenAal("not-a-token")).toBeNull();
    expect(tokenAal(undefined)).toBeNull();
  });
});

describe("who still owes the code", () => {
  test("someone with an app and a password-only token", () => {
    expect(secondStepPending(withApp, token({ aal: "aal1" }))).toBe(true);
    expect(secondStepPending(withApp, token({}))).toBe(true);
  });

  test("not once the code has been entered", () => {
    expect(secondStepPending(withApp, token({ aal: "aal2" }))).toBe(false);
  });

  test("not someone without an app, or whose set-up was never finished", () => {
    expect(secondStepPending({ factors: [] }, token({ aal: "aal1" }))).toBe(false);
    expect(secondStepPending({}, token({ aal: "aal1" }))).toBe(false);
    expect(secondStepPending(halfSetUp, token({ aal: "aal1" }))).toBe(false);
  });
});

describe("where the code page returns to", () => {
  test("a path on this site", () => {
    expect(safeNext("/tasks?filter=all")).toBe("/tasks?filter=all");
  });

  test("never anywhere else", () => {
    expect(safeNext("https://elsewhere.example")).toBe("/dashboard");
    expect(safeNext("//elsewhere.example")).toBe("/dashboard");
    expect(safeNext(null)).toBe("/dashboard");
  });
});

// --- the middleware ------------------------------------------------------------

let user: { id: string; user_metadata: object; factors?: { status: string }[] } | null;
let accessToken: string;

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: {
      getUser: async () => ({ data: { user } }),
      getSession: async () => ({ data: { session: { access_token: accessToken } } }),
    },
  }),
}));

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";

const { updateSession } = await import("@/lib/supabase/middleware");
const ask = (path: string) => updateSession(new NextRequest(`https://portal.test${path}`));

describe("the middleware", () => {
  beforeEach(() => {
    user = { id: "u1", user_metadata: {}, factors: [{ status: "verified" }] };
    accessToken = token({ aal: "aal1" });
  });

  test("sends a password-only session to the code page, remembering where it was going", async () => {
    const response = await ask("/tasks?filter=all");
    expect(response.status).toBe(307);
    const to = new URL(response.headers.get("location")!);
    expect(to.pathname).toBe("/login/verify");
    expect(to.searchParams.get("next")).toBe("/tasks?filter=all");
  });

  test("lets it through once the code is in", async () => {
    accessToken = token({ aal: "aal2" });
    const response = await ask("/tasks");
    expect(response.headers.get("location")).toBeNull();
  });

  test("leaves the code page itself, and signing out, reachable", async () => {
    for (const path of ["/login/verify", "/auth/signout"]) {
      expect((await ask(path)).headers.get("location")).toBeNull();
    }
  });

  test("leaves everybody without an app alone", async () => {
    user = { id: "u1", user_metadata: {} };
    expect((await ask("/tasks")).headers.get("location")).toBeNull();
  });
});

describe("the QR code", () => {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect style="fill:#000000"/></svg>';

  test("is encoded, so its # colours do not end the URL", () => {
    const src = qrSource(`data:image/svg+xml;utf-8,${svg}`);
    expect(src).not.toContain("#");
    expect(decodeURIComponent(src.slice(src.indexOf(",") + 1))).toBe(svg);
  });

  test("bare, or already encoded, comes out the same", () => {
    const expected = qrSource(`data:image/svg+xml;utf-8,${svg}`);
    expect(qrSource(svg)).toBe(expected);
    expect(qrSource(`data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`)).toBe(expected);
  });
});
