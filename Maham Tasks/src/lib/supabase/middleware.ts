import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

import type { Database } from "./database.types";
import { isSupabaseConfigured, supabaseAnonKey, supabaseUrl } from "./env";
import { hasAuthenticator, secondStepPending } from "./second-step";

/**
 * Routes reachable without a session. Everything else requires sign-in.
 *
 * Prefix matching is used for these, so "/auth" also covers "/auth/callback".
 * The landing page is matched exactly — treating "/" as a prefix would make
 * the entire app public.
 */
const PUBLIC_PREFIXES = [
  "/login",
  "/register",
  "/auth",
  "/forgot-password",
  // Machine-to-machine endpoints. These never carry a user session — the cron
  // dispatcher and the Telegram webhook authenticate with their own shared
  // secrets — so redirecting them to /login would silently stop reminders.
  "/api/reminders",
  "/api/telegram",
  // For an uptime monitor, which has no account. It says whether the
  // database answers and how far the migrations have run, nothing more.
  "/api/health",
  // The page the service worker shows when there is no connection. It holds
  // nothing private, and gating it would mean the one page meant to work
  // without the network needs the network to check a session.
  "/offline",
];
const PUBLIC_EXACT = ["/"];

/**
 * Headers this middleware writes for the render that follows it.
 *
 * The middleware already verifies the session with Supabase on every request.
 * Doing it again inside the render cost a second round trip to the auth server
 * on the critical path of every page — the same question, the same answer,
 * 120ms later. These carry the answer forward instead.
 *
 * They are stripped from the incoming request before anything else happens, on
 * every path through this function, so a header a browser sent can never be
 * mistaken for one this middleware wrote. The matcher covers every route, so
 * there is no way into the app that skips the strip.
 */
export const VERIFIED_USER = "x-almail-user";
export const VERIFIED_MUST_CHANGE_PASSWORD = "x-almail-password-change";

function isPublicRoute(pathname: string) {
  if (PUBLIC_EXACT.includes(pathname)) return true;
  return PUBLIC_PREFIXES.some(
    (route) => pathname === route || pathname.startsWith(`${route}/`),
  );
}

/**
 * Refreshes the Supabase auth session on every request and gates private
 * routes.
 *
 * The `supabaseResponse` object must be returned as-is — replacing it would
 * drop the refreshed auth cookies and silently log users out.
 */
export async function updateSession(request: NextRequest) {
  // First, and on every path out of here: whatever the browser sent under
  // these names is discarded. Only this function may write them.
  const headers = new Headers(request.headers);
  headers.delete(VERIFIED_USER);
  headers.delete(VERIFIED_MUST_CHANGE_PASSWORD);
  const forward = { headers };

  let supabaseResponse = NextResponse.next({ request: forward });

  // Without credentials there is no session to refresh, and any authenticated
  // page would throw when it built a client. Send those to the landing page,
  // which explains what is missing, instead of surfacing a 500.
  if (!isSupabaseConfigured()) {
    if (isPublicRoute(request.nextUrl.pathname)) return supabaseResponse;

    const setupUrl = request.nextUrl.clone();
    setupUrl.pathname = "/";
    setupUrl.search = "";
    return NextResponse.redirect(setupUrl);
  }

  const supabase = createServerClient<Database>(
    supabaseUrl(),
    supabaseAnonKey(),
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          supabaseResponse = NextResponse.next({ request: forward });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Do not insert logic between client creation and getUser(): getUser()
  // revalidates the token with Supabase and is what refreshes the cookies.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;

  if (!user && !isPublicRoute(pathname)) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/login";
    // Preserve the destination so sign-in can return the user to it.
    redirectUrl.searchParams.set("next", pathname);
    return NextResponse.redirect(redirectUrl);
  }

  // Two-step sign-in: a session with the password but not yet the code goes
  // to the code page, wherever it was headed. The database treats such a
  // session as a member's whatever this does (second_step_pending); this is
  // what makes the app say so instead of quietly showing less. Only people
  // with an app are looked at twice; for everybody else this costs nothing.
  if (user && hasAuthenticator(user) && !isPublicRoute(pathname)) {
    const {
      data: { session },
    } = await supabase.auth.getSession();
    if (secondStepPending(user, session?.access_token)) {
      const verifyUrl = request.nextUrl.clone();
      verifyUrl.pathname = "/login/verify";
      verifyUrl.search = "";
      verifyUrl.searchParams.set("next", `${pathname}${request.nextUrl.search}`);
      const redirect = NextResponse.redirect(verifyUrl);
      supabaseResponse.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie));
      return redirect;
    }
  }

  if (user && (pathname === "/login" || pathname === "/register")) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/dashboard";
    redirectUrl.search = "";
    return NextResponse.redirect(redirectUrl);
  }

  // Hand the verified identity to the render. `getAuthUser` reads these rather
  // than asking the auth server the same question a second time.
  if (user) {
    headers.set(VERIFIED_USER, user.id);
    headers.set(
      VERIFIED_MUST_CHANGE_PASSWORD,
      user.user_metadata?.must_change_password === true ? "1" : "0",
    );
    // The response was built before the headers were known, so rebuild it —
    // keeping any refreshed auth cookies, which is the whole point of the
    // dance above.
    const withIdentity = NextResponse.next({ request: forward });
    supabaseResponse.cookies
      .getAll()
      .forEach((cookie) => withIdentity.cookies.set(cookie));
    return withIdentity;
  }

  return supabaseResponse;
}
