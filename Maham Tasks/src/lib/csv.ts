import { priorityMeta, statusMeta } from "@/lib/constants";
import { en } from "@/lib/i18n/en";
import type { TranslationKey } from "@/lib/i18n";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * A task list as a spreadsheet.
 *
 * The one export a company portal is actually asked for: the list as it is
 * on screen — same filters, same order — as a file someone can send on, sort
 * in Excel, or paste into a report.
 */

/** RFC 4180: quote anything with a comma, quote or newline; double quotes. */
export function csvCell(value: string | number | null | undefined): string {
  const text = value === null || value === undefined ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function tasksToCsv(
  tasks: TaskWithAssignees[],
  projectName?: (projectId: string | null) => string,
  /** The reader's translator; the file is written in their language. */
  t: (key: TranslationKey) => string = (key) => en[key],
): string {
  const header = [
    t("csv.title"),
    ...(projectName ? [t("csv.project")] : []),
    t("csv.status"),
    t("csv.priority"),
    t("csv.due"),
    t("csv.assignees"),
    t("csv.created"),
    t("csv.description"),
  ];

  const rows = tasks.map((task) => [
    task.title,
    ...(projectName ? [projectName(task.project_id)] : []),
    t(statusMeta(task.status).label),
    t(priorityMeta(task.priority).label),
    task.due_at ?? "",
    task.assignees.map((p) => p.full_name ?? p.email).join("; "),
    task.created_at,
    task.description ?? "",
  ]);

  // CRLF line endings: what Excel expects, and what the RFC specifies. The
  // byte-order mark is how Excel is told the file is UTF-8 — without it an
  // Arabic title opens as a row of question marks.
  return (
    "\uFEFF" +
    [header, ...rows].map((row) => row.map(csvCell).join(",")).join("\r\n") +
    "\r\n"
  );
}

/** A filename that sorts by date and says what it is. */
export function csvFilename(scope: string): string {
  const stamp = new Date().toISOString().slice(0, 10);
  const slug = scope.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `${slug || "tasks"}-${stamp}.csv`;
}
