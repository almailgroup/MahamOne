/**
 * The middleware hands the render an identity it has just verified, which
 * saves a round trip to the auth server on every page. That is only sound if
 * the headers it uses cannot be written by anybody else — so this is the test
 * that matters: a browser that sends them must never be believed.
 */

import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const USER = "00000000-0000-4000-8000-000000000001";

let user: { id: string; user_metadata: Record<string, unknown> } | null = null;
/** Cookies the Supabase client refreshes mid-request, if any. */
let refreshed: { name: string; value: string; options: object }[] = [];

vi.mock("@supabase/ssr", () => ({
  createServerClient: (
    _url: string,
    _key: string,
    options: { cookies: { setAll: (c: unknown[]) => void } },
  ) => ({
    auth: {
      getUser: async () => {
        // The real client writes refreshed cookies through this callback
        // before it answers, which is what rebuilding the response risks
        // throwing away.
        if (refreshed.length) options.cookies.setAll(refreshed);
        return { data: { user } };
      },
    },
  }),
}));

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "anon";

const { updateSession, VERIFIED_USER, VERIFIED_MUST_CHANGE_PASSWORD } =
  await import("@/lib/supabase/middleware");

/** What the render will see, which is the request headers the middleware set. */
const forwarded = (response: Response) =>
  new Headers(response.headers.get("x-middleware-override-headers")
    ? Object.fromEntries(
        response.headers
          .get("x-middleware-override-headers")!
          .split(",")
          .map((name) => [
            name.trim(),
            response.headers.get(`x-middleware-request-${name.trim()}`) ?? "",
          ]),
      )
    : {});

const ask = (path: string, headers: Record<string, string> = {}) =>
  updateSession(new NextRequest(`https://portal.test${path}`, { headers }));

describe("the verified-identity headers", () => {
  beforeEach(() => {
    user = { id: USER, user_metadata: {} };
    refreshed = [];
  });

  test("are set from the user the middleware just verified", async () => {
    const sent = forwarded(await ask("/today"));
    expect(sent.get(VERIFIED_USER)).toBe(USER);
    expect(sent.get(VERIFIED_MUST_CHANGE_PASSWORD)).toBe("0");
  });

  test("carry the password-change flag off the user, not off the request", async () => {
    user = { id: USER, user_metadata: { must_change_password: true } };
    const sent = forwarded(await ask("/today", { [VERIFIED_MUST_CHANGE_PASSWORD]: "0" }));
    expect(sent.get(VERIFIED_MUST_CHANGE_PASSWORD)).toBe("1");
  });

  /**
   * The one that matters. Believing this header would let anyone read any
   * account's board by typing a uuid into a request.
   */
  test("never carry a value the browser sent", async () => {
    const forged = "11111111-1111-4111-8111-111111111111";
    const sent = forwarded(await ask("/today", { [VERIFIED_USER]: forged }));
    expect(sent.get(VERIFIED_USER)).toBe(USER);
    expect(sent.get(VERIFIED_USER)).not.toBe(forged);
  });

  test("are stripped, not merely overwritten, when there is nobody to verify", async () => {
    user = null;
    const forged = "11111111-1111-4111-8111-111111111111";
    // A public route: no session, and the middleware lets it through rather
    // than redirecting — so this is the path where a forged header would
    // survive if it were only overwritten inside the `if (user)` branch.
    const sent = forwarded(await ask("/login", { [VERIFIED_USER]: forged }));
    expect(sent.get(VERIFIED_USER)).toBeNull();
  });

  test("are stripped on a machine-to-machine route too", async () => {
    user = null;
    const forged = "11111111-1111-4111-8111-111111111111";
    const sent = forwarded(await ask("/api/reminders/run", { [VERIFIED_USER]: forged }));
    expect(sent.get(VERIFIED_USER)).toBeNull();
  });
});

/**
 * The middleware builds a fresh response once it knows who is asking, and a
 * refreshed session cookie that does not survive that is a silent sign-out —
 * the failure the original "return supabaseResponse as-is" comment warns
 * about, and the reason this test exists rather than a careful reading.
 */
describe("a session refreshed mid-request", () => {
  beforeEach(() => {
    user = { id: USER, user_metadata: {} };
    refreshed = [
      { name: "sb-test-auth-token", value: "fresh", options: { path: "/" } },
    ];
  });

  test("still reaches the browser", async () => {
    const response = await ask("/today");
    expect(response.cookies.get("sb-test-auth-token")?.value).toBe("fresh");
  });

  test("reaches it on a public route too", async () => {
    user = null;
    const response = await ask("/login");
    expect(response.cookies.get("sb-test-auth-token")?.value).toBe("fresh");
  });
});
