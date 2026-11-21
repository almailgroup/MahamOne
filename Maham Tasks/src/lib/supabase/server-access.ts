import "server-only";

import { createClient as createSupabaseClient, type PostgrestError } from "@supabase/supabase-js";

/**
 * The server's own access to the database. SERVER ONLY.
 *
 * Maham Tasks runs on Maham One's database, where the service key would open
 * everything: payroll, Civil IDs, every company's books. So the server holds
 * no such key. It holds TASKS_SERVER_SECRET, which opens the tasks.srv_*
 * functions of supabase/migrations/20261212000000_maham_tasks.sql and nothing
 * else; each checks the secret, then does one thing to Maham Tasks' own
 * tables (claim reminders, mark one sent, read the holidays…).
 *
 *   * the variable is NOT prefixed NEXT_PUBLIC_, so Next.js never inlines it
 *     into a browser bundle
 *   * this module imports "server-only", so importing it from a Client
 *     Component is a build error rather than a silent leak
 *
 * Calls go out with the publishable key and no session, as `anon`; the
 * secret is what lets them through. Anything that serves a user request uses
 * `@/lib/supabase/server` instead, which runs as the signed-in user.
 */

export type ServerResult<T> = { data: T | null; error: PostgrestError | null };

export interface ServerAccess {
  /** Runs one of the server's jobs: tasks.srv_<job>, with the secret. */
  rpc<T = unknown>(job: string, args?: Record<string, unknown>): Promise<ServerResult<T>>;
}

export function createServerAccess(): ServerAccess {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const secret = process.env.TASKS_SERVER_SECRET;

  if (!url || !key || !secret) {
    throw new Error(
      "This needs NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY and TASKS_SERVER_SECRET in the server environment.",
    );
  }

  const client = createSupabaseClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "tasks" },
  });

  return {
    async rpc<T>(job: string, args: Record<string, unknown> = {}) {
      const { data, error } = await client.rpc(`srv_${job}`, { p_secret: secret, ...args });
      return { data: (data ?? null) as T | null, error };
    },
  };
}
