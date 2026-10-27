import "server-only";

import webpush from "web-push";

import { createAdminClient } from "@/lib/supabase/admin";

/**
 * The VAPID key pair.
 *
 * A push has to be signed by the same key the browser subscribed with, so the
 * pair has to outlive a deployment. The usual place is an environment
 * variable, which means somebody generates a secret, copies it out of a
 * terminal and pastes it into a dashboard — the kind of handling that ends
 * with the private half in a chat log.
 *
 * Instead it is generated here on first use and kept in `web_push_keys`, a
 * table with row-level security on and no policies: nothing holding a user's
 * session can read it, only the service role this runs as. It is written
 * once; the primary key is a boolean fixed at true, so two servers racing to
 * create it produce one row and one of them reads the winner's.
 */
export type VapidKeys = { publicKey: string; privateKey: string };

/** Cached per server instance: the row never changes once it exists. */
let cached: VapidKeys | null = null;

export async function vapidKeys(): Promise<VapidKeys | null> {
  if (cached) return cached;

  const supabase = createAdminClient();

  const existing = await supabase
    .from("web_push_keys")
    .select("public_key, private_key")
    .maybeSingle();

  if (existing.data) {
    cached = {
      publicKey: existing.data.public_key,
      privateKey: existing.data.private_key,
    };
    return cached;
  }

  // Not there yet. Generate, and let the database settle a race.
  const generated = webpush.generateVAPIDKeys();
  const inserted = await supabase
    .from("web_push_keys")
    .insert({
      id: true,
      public_key: generated.publicKey,
      private_key: generated.privateKey,
    })
    .select("public_key, private_key")
    .maybeSingle();

  if (inserted.data) {
    cached = {
      publicKey: inserted.data.public_key,
      privateKey: inserted.data.private_key,
    };
    return cached;
  }

  // Somebody else won: read theirs rather than insisting on ours, which is
  // the whole point of the single-row constraint.
  const winner = await supabase
    .from("web_push_keys")
    .select("public_key, private_key")
    .maybeSingle();

  if (!winner.data) return null;

  cached = {
    publicKey: winner.data.public_key,
    privateKey: winner.data.private_key,
  };
  return cached;
}

/**
 * The half the browser needs, and the only half that ever leaves the server.
 */
export async function publicPushKey(): Promise<string | null> {
  const keys = await vapidKeys();
  return keys?.publicKey ?? null;
}

/**
 * Who a push says it is from.
 *
 * VAPID wants a contact for the push service to reach if something is wrong
 * with the sender. The site URL is the honest answer and is already set.
 */
export function pushSubject(): string {
  const site = process.env.NEXT_PUBLIC_SITE_URL;
  return site && site.startsWith("https://") ? site : "mailto:admin@almailgroup.com";
}
