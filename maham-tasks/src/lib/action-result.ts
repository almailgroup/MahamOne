/**
 * Uniform result type for Server Actions.
 *
 * Actions never throw for expected failures (bad input, denied by RLS) — they
 * return a result the form can render. `fieldErrors` maps a form field name to
 * its first message.
 */
export type ActionResult<T = void> =
  | { ok: true; data: T }
  | { ok: false; error: string; fieldErrors?: Record<string, string> };

export const ok = <T,>(data: T): ActionResult<T> => ({ ok: true, data });

export const fail = (
  error: string,
  fieldErrors?: Record<string, string>,
): ActionResult<never> => ({ ok: false, error, fieldErrors });

/** Flatten a ZodError's issues into one message per field. */
export function fieldErrorsFrom(
  issues: { path: (string | number)[]; message: string }[],
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const issue of issues) {
    const key = String(issue.path[0] ?? "form");
    if (!(key in result)) result[key] = issue.message;
  }
  return result;
}

/**
 * The messages the database raises itself, in the SQL under supabase/, each
 * mapped to its dictionary key so they can be shown in the reader's language.
 * Anything else the database says is shown as it is.
 */
const RAISED_BY_SQL: Record<string, string> = {
  "Only a manager or admin can mark a task done. Move it to In Review instead.": "kanban.doneGate",
  "Only a manager or admin can reopen a completed task.": "kanban.reopenGate",
  "Cannot remove the last admin. Promote another member first.": "db.lastAdmin",
  "Only an admin can change a profile role": "db.roleAdminOnly",
  "Only an admin can change a job position": "db.positionAdminOnly",
  "Only a manager or admin can change task details. You can update the status and add comments or files.":
    "db.detailsManagerOnly",
  "That milestone belongs to another project.": "milestone.otherProject",
  "A milestone stays in its project.": "milestone.staysInProject",
};

/**
 * Turn a PostgREST error into something a user can act on.
 *
 * RLS denials surface as 42501 (insufficient privilege) or as an empty result;
 * both mean "you are not allowed to do this", not "something broke".
 *
 * Returns a dictionary key where one fits, so the client can show it in the
 * reader's language; the client's `tm` passes any other text through.
 */
export function describeDatabaseError(error: {
  code?: string;
  message?: string;
}): string {
  const known = error.message ? RAISED_BY_SQL[error.message] : undefined;
  if (known) return known;

  switch (error.code) {
    case "42501":
      // The review gate and the task-field guard raise this with a message
      // written for the user, so prefer it over the generic line.
      return error.message || "db.noPermission";
    case "23505":
    case "23505_unique":
      return "db.exists";
    case "23503":
      return "db.gone";
    case "23514":
      return "db.notAllowed";
    case "PGRST116":
      return "db.notFound";
    default:
      return error.message || "common.somethingWrong";
  }
}
