/**
 * Turning Supabase's auth errors into something a person can act on.
 *
 * They arrive as lowercase fragments written for whoever is reading the logs —
 * "email rate limit exceeded" — and were being shown to the person signing up
 * word for word. Each one below says what happened, whether anything was
 * saved, and what to do next.
 *
 * Every recognised failure is returned as a dictionary key, so the form can
 * show it in the reader's language; a fragment nobody anticipated is tidied
 * into a sentence and shown as it is.
 */

type AuthErrorLike = { message?: string; status?: number; code?: string };

/**
 * Whether a failed sign-in was simply the wrong email or password.
 *
 * This is the one failure that must stay vague — saying which half was wrong,
 * or that no such account exists, hands anyone a way to test which of the
 * company's addresses are registered. Every other failure is safe to name, and
 * far more useful named.
 */
export function isWrongCredentials(error: AuthErrorLike): boolean {
  return (
    error.code === "invalid_credentials" ||
    (error.message ?? "").toLowerCase().includes("invalid login credentials")
  );
}

export function describeAuthError(error: AuthErrorLike): string {
  const message = (error.message ?? "").toLowerCase();
  const code = (error.code ?? "").toLowerCase();

  /**
   * The cap on confirmation emails, which is Supabase's built-in mail service
   * rather than anything this app controls. It is a handful an hour, meant for
   * development, and a workspace onboarding its staff runs through it quickly.
   */
  if (
    code === "over_email_send_rate_limit" ||
    message.includes("rate limit") ||
    (error.status === 429 && message.includes("email"))
  ) {
    return "auth.emailCap";
  }

  // A blanket 429 that is not about email: repeated attempts from one address.
  if (error.status === 429 || code === "over_request_rate_limit") {
    return "auth.tooManyAttempts";
  }

  if (
    code === "user_already_exists" ||
    message.includes("already registered") ||
    message.includes("already been registered")
  ) {
    return "auth.accountExists";
  }

  if (code === "signup_disabled" || message.includes("signups not allowed")) {
    return "auth.signupsOff";
  }

  if (message.includes("for security purposes")) {
    return "auth.momentAgo";
  }

  if (code === "weak_password" || message.includes("password should be")) {
    return "auth.weakPassword";
  }

  if (message.includes("unable to validate email") || code === "validation_failed") {
    return "auth.emailLooksWrong";
  }

  if (message.includes("email not confirmed")) {
    return "auth.needsConfirming";
  }

  if (error.status === 0 || message.includes("fetch failed") || message.includes("network")) {
    return "auth.noNetwork";
  }

  /**
   * The sign-in service itself failed — a 500 from the auth server, or a 502
   * or 504 from in front of it. Nothing the person typed is wrong, and telling
   * them otherwise sends them round retyping a password that was right. The
   * status code goes to the server log, where whoever is on call can see it.
   */
  if (typeof error.status === "number" && error.status >= 500) {
    console.error(`[auth] the auth service answered ${error.status}`);
    return "auth.serviceDown";
  }

  // Anything unrecognised: show it, but as a sentence rather than a fragment.
  const raw = (error.message ?? "").trim();
  if (!raw) return "common.somethingWrong";
  const sentence = raw.charAt(0).toUpperCase() + raw.slice(1);
  return /[.!?]$/.test(sentence) ? sentence : `${sentence}.`;
}
