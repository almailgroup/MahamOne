/**
 * Server faults, recorded where somebody will see them.
 *
 * Next calls this for every error thrown while rendering or handling a
 * request — including the ones the error boundary shows a generic page for,
 * which is precisely the set nobody was finding out about.
 *
 * Written with the service role because the request that failed may have had
 * no session, and because a fault should be recorded whether or not the
 * person who hit it is allowed to read it back. Nothing here is fatal: if
 * the recording fails, the error is still an error and the page still says
 * so.
 */
export async function onRequestError(
  error: unknown,
  request: { path?: string; headers?: Record<string, string | undefined> },
): Promise<void> {
  try {
    const { createAdminClient } = await import("@/lib/supabase/admin");
    const supabase = createAdminClient();

    const message =
      error instanceof Error
        ? `${error.name}: ${error.message}`
        : String(error ?? "Unknown error");

    await supabase.from("app_errors").insert({
      source: "server",
      // Next's own reference, the one printed on the error page, so somebody
      // quoting it can be matched to this row.
      digest: (error as { digest?: string })?.digest ?? null,
      message: message.slice(0, 2000),
      route: request.path?.slice(0, 500) ?? null,
      user_agent: request.headers?.["user-agent"]?.slice(0, 400) ?? null,
      user_id: null,
    });
  } catch {
    // A logger that throws is worse than no logger.
  }
}
