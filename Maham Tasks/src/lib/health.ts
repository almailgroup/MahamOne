import { isMissingFunction } from "@/lib/supabase/missing";

/**
 * What /api/health says, worked out from what the database answered.
 *
 * Three states, for an uptime monitor and for a person reading it:
 * - ok: the database answers and every migration this code needs is run;
 * - degraded: it answers, but the migrations are behind the code — the app
 *   mostly works, newer features wait (HTTP 200: the site is up);
 * - down: it does not answer (HTTP 503).
 */

/** The newest migration this code knows about. Bump it with each one. */
export const EXPECTED_SCHEMA = 46;

export type HealthReport = {
  status: "ok" | "degraded" | "down";
  database: "ok" | "unreachable" | "not configured";
  /** The newest migration run, or null when the database could not say. */
  schema: number | null;
  expected: number;
  /** Older migrations that were skipped. */
  missing: number[];
  latencyMs: number | null;
  /** The deployed commit, so "which version is this" has an answer. */
  commit: string | null;
};

type Answer = {
  data: { database?: string; schema?: number; missing?: number[] } | null;
  error: { code?: string; message?: string } | null;
};

export function healthReport(
  answer: Answer | "not configured" | "timed out",
  { latencyMs = null, commit = null }: { latencyMs?: number | null; commit?: string | null } = {},
): HealthReport {
  const base = { expected: EXPECTED_SCHEMA, missing: [] as number[], latencyMs, commit };

  if (answer === "not configured") {
    return { ...base, status: "down", database: "not configured", schema: null, latencyMs: null };
  }
  if (answer === "timed out") {
    return { ...base, status: "down", database: "unreachable", schema: null };
  }
  if (answer.error) {
    // It answered, but has never heard of the function: migration 46 is
    // not run, so the schema is behind, by an unknown amount.
    if (isMissingFunction(answer.error)) {
      return { ...base, status: "degraded", database: "ok", schema: null };
    }
    return { ...base, status: "down", database: "unreachable", schema: null };
  }

  const schema = answer.data?.schema ?? null;
  const missing = answer.data?.missing ?? [];
  const behind = schema === null || schema < EXPECTED_SCHEMA || missing.length > 0;
  return { ...base, status: behind ? "degraded" : "ok", database: "ok", schema, missing };
}
