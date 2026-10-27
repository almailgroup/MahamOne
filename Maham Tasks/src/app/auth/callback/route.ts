import { NextResponse, type NextRequest } from "next/server";

import { createClient } from "@/lib/supabase/server";

/**
 * Email confirmation / magic-link landing route.
 *
 * Supabase redirects here with a one-time `code`, which we exchange for a
 * session before forwarding the user on.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const next = searchParams.get("next");

  // Only relative paths, to keep this from becoming an open redirect.
  const destination =
    next && next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";

  if (!code) {
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent("That confirmation link is invalid.")}`,
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(
      `${origin}/login?error=${encodeURIComponent("That confirmation link has expired. Please sign in again.")}`,
    );
  }

  return NextResponse.redirect(`${origin}${destination}`);
}
