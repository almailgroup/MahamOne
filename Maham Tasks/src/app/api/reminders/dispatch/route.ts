import { NextResponse, type NextRequest } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import { sweep } from "@/lib/reminders/sweep";

/**
 * Drains the reminder queue.
 *
 * Called on a schedule (Vercel Cron, or Supabase pg_cron) and authenticated by
 * a shared secret, because it runs with the service-role key and must not be
 * reachable by anyone else. Vercel Cron sends the secret as a Bearer token;
 * anything else can pass the same value as x-cron-secret.
 *
 * What a run does, and on which days it stays quiet, is lib/reminders/sweep.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function authorised(request: NextRequest): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;

  const header = request.headers.get("authorization");
  if (header === `Bearer ${secret}`) return true;

  return request.headers.get("x-cron-secret") === secret;
}

export async function GET(request: NextRequest) {
  return run(request);
}

export async function POST(request: NextRequest) {
  return run(request);
}

async function run(request: NextRequest) {
  if (!authorised(request)) {
    // Deliberately terse: this endpoint should look like nothing to a stranger.
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // A missing service-role key is the commonest first-deploy mistake, so say
  // so plainly instead of returning an opaque 500.
  let supabase;
  try {
    supabase = createAdminClient();
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "Reminder delivery is not configured.",
        hint: "Set SUPABASE_SERVICE_ROLE_KEY in the server environment. It must NOT be prefixed NEXT_PUBLIC_.",
      },
      { status: 503 },
    );
  }

  try {
    return NextResponse.json(await sweep(supabase));
  } catch (error) {
    console.error("[reminders]", error);
    return NextResponse.json(
      { error: "Could not read the reminder queue." },
      { status: 500 },
    );
  }
}
