import { NextResponse, type NextRequest } from "next/server";

import { createClient } from "@/lib/supabase/server";

/**
 * Clears the session and returns to sign-in.
 *
 * This exists as a route handler rather than living in `requireProfile()`
 * because a Server Component cannot write cookies, so it cannot actually end a
 * session. Without somewhere to land that *can*, a signed-in user whose
 * profile row is missing bounces forever: the page redirects to /login, the
 * middleware sees a valid session and sends them back.
 *
 * `/auth` is a public prefix in the middleware, so this route is reachable
 * while signed in, and once the session is gone there is nothing to bounce.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const reason = searchParams.get("error");

  const supabase = await createClient();
  await supabase.auth.signOut();

  const target = new URL("/login", origin);
  if (reason) target.searchParams.set("error", reason);

  return NextResponse.redirect(target);
}
