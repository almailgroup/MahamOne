import "server-only";

import webpush from "web-push";

import { createServerAccess } from "@/lib/supabase/server-access";

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
 * session can read it, only the server, through tasks.srv_web_push_keys. It is written
 * once; the primary key is a boolean fixed at true, so two servers racing to
 * create it produce one row and one of them reads the winner's.
 */
export type VapidKeys = { publicKey: string; privateKey: string };

/** Cached per server instance: the row never changes once it exists. */
let cached: VapidKeys | null = null;

export async function vapidKeys(): Promise<VapidKeys | null> {
  if (cached) return cached;

  const supabase = createServerAccess();
  type Row = { public_key: string; private_key: string };

  // The stored pair, when there is one.
  const existing = await supabase.rpc<Row[]>("web_push_keys", { p_public: null, p_private: null });
  let row = existing.data?.[0];

  if (!row) {
    // Not there yet. Generate, and let the database settle a race: it keeps
    // the first pair and hands back whichever it kept.
    const generated = webpush.generateVAPIDKeys();
    const kept = await supabase.rpc<Row[]>("web_push_keys", {
      p_public: generated.publicKey,
      p_private: generated.privateKey,
    });
    row = kept.data?.[0];
  }

  if (!row) return null;
  cached = { publicKey: row.public_key, privateKey: row.private_key };
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
