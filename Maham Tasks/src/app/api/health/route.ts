import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

import { healthReport } from "@/lib/health";
import { isSupabaseConfigured, supabaseAnonKey, supabaseUrl } from "@/lib/supabase/env";

/**
 * For an uptime monitor: is the portal up, does its database answer, and
 * have the migrations been run as far as this code needs?
 *
 * Public, and asked with the public key alone: no session, no service key,
 * and nothing in the answer about anybody (portal_health, migration 46).
 * 503 only when the database cannot be reached; a database behind the code
 * is "degraded" with a 200, because the site itself is up.
 */

export const dynamic = "force-dynamic";

const TIMEOUT_MS = 5_000;

export async function GET() {
  const commit = process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? null;

  if (!isSupabaseConfigured()) {
    return respond(healthReport("not configured", { commit }));
  }

  const supabase = createClient(supabaseUrl(), supabaseAnonKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const started = Date.now();
  const answer = await Promise.race([
    supabase.rpc("portal_health").then(({ data, error }) => ({ data, error })),
    new Promise<"timed out">((resolve) => setTimeout(() => resolve("timed out"), TIMEOUT_MS)),
  ]).catch(() => "timed out" as const);

  return respond(healthReport(answer, { latencyMs: Date.now() - started, commit }));
}

function respond(report: ReturnType<typeof healthReport>) {
  return NextResponse.json(report, {
    status: report.status === "down" ? 503 : 200,
    headers: { "Cache-Control": "no-store" },
  });
}
