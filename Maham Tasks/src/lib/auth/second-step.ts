import "server-only";

import type { createClient } from "@/lib/supabase/server";
import { tokenAal } from "@/lib/supabase/second-step";

type Client = Awaited<ReturnType<typeof createClient>>;

/**
 * Whether this session entered a code from an authenticator app as well as
 * the password.
 *
 * What an admin needs before the actions that run with the service key —
 * adding people, resetting passwords — and before changing anybody's role.
 * Somebody who has not set one up yet is aal1 here, and is told to.
 *
 * Read off the access token: every caller has had that token verified by the
 * auth server already on this request (getUser in an action, the middleware
 * for a page), and its signature is what makes the claim worth believing.
 * Asking getAuthenticatorAssuranceLevel() instead reads the unverified user
 * out of the cookie, and logs a warning saying so on every call.
 */
export async function signedInWithSecondStep(supabase: Client): Promise<boolean> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return tokenAal(session?.access_token) === "aal2";
}
