/**
 * Two-step sign-in, as the token tells it.
 *
 * Supabase stamps every access token with how it was earned: `aal1` after a
 * password, `aal2` after the code from an authenticator app as well. Someone
 * who has an app but holds an aal1 token has done half of signing in.
 *
 * Read from the token rather than asked of the auth server: the middleware
 * has already verified the user once on this request, and the token it holds
 * is the one that verification refreshed.
 */

type WithFactors = { factors?: { status: string }[] | null };

/** The `aal` claim of a Supabase access token, or null when it has none. */
export function tokenAal(accessToken: string | null | undefined): string | null {
  const payload = accessToken?.split(".")[1];
  if (!payload) return null;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
    const claims = JSON.parse(atob(padded)) as { aal?: unknown };
    return typeof claims.aal === "string" ? claims.aal : null;
  } catch {
    return null;
  }
}

/** Whether this person has an authenticator app they finished setting up. */
export function hasAuthenticator(user: WithFactors): boolean {
  return user.factors?.some((factor) => factor.status === "verified") ?? false;
}

/** Signed in with the password, but the code is still owed. */
export function secondStepPending(user: WithFactors, accessToken: string | null | undefined) {
  return hasAuthenticator(user) && tokenAal(accessToken) !== "aal2";
}

/**
 * Only same-site paths, so `?next=https://elsewhere` cannot turn the code
 * page into a way off the site.
 */
export function safeNext(next: string | null | undefined): string {
  if (!next || !next.startsWith("/") || next.startsWith("//")) return "/dashboard";
  return next;
}

/**
 * The QR code as an image source that every browser draws.
 *
 * Supabase's client hands it over as `data:image/svg+xml;utf-8,<svg…>` with
 * the SVG unencoded, and the SVG's colours are written `#000000` — which a
 * browser reads as the start of a fragment, cutting the image off at its
 * first colour and showing a broken-image box. So the SVG is taken back out
 * and encoded properly.
 */
export function qrSource(qr: string) {
  if (/^data:[^,]*;base64,/.test(qr)) return qr;
  let svg = qr.replace(/^data:[^,]*,/, "");
  if (!svg.trimStart().startsWith("<")) {
    try {
      svg = decodeURIComponent(svg);
    } catch {
      // Not encoded after all; use it as it is.
    }
  }
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}
