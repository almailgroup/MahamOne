import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import type { Database } from "./database.types";

/**
 * Service-role client. SERVER ONLY.
 *
 * This key bypasses every Row Level Security policy in the schema, so it is
 * deliberately the single place in the codebase that touches it:
 *
 *   * the variable is NOT prefixed NEXT_PUBLIC_, so Next.js will never inline
 *     it into a browser bundle
 *   * this module imports "server-only", so importing it from a Client
 *     Component is a build error rather than a silent leak
 *   * it has two callers, and both need to act outside any one user's view:
 *     the reminder dispatcher, which reads every user's queued reminders, and
 *     adding a teammate, which creates an auth user
 *
 * Anything else that serves a user request should use `@/lib/supabase/server`,
 * which runs as the signed-in user and is governed by RLS. A caller here must
 * check the caller's own role first — there is no policy left to do it.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "This needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the server environment.",
    );
  }

  return createSupabaseClient<Database>(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Whether the service-role key is present.
 *
 * Adding a teammate needs it, and finding that out only after filling in the
 * form and pressing the button is a poor way to learn. The Team page asks
 * first and says so instead.
 */
export function hasServiceRole(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
}
