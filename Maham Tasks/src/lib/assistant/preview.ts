import { formatDateTime } from "@/lib/dates";
import { statusMeta, priorityMeta } from "@/lib/constants";
import type { Translator } from "@/lib/i18n";
import type { AssistantAction, AssistantSnapshot } from "@/lib/assistant/types";
import type { TaskPriority, TaskStatus } from "@/lib/supabase/database.types";

/**
 * A proposal, written out for the person who has to agree to it.
 *
 * Resolved here, on the server, where the snapshot still is: the model deals
 * in ids and instants, and neither belongs in front of somebody deciding
 * whether to press Confirm. A card reading "Freight · Sara Khan · 20 Sep,
 * 5:00 PM" can be checked at a glance; one reading
 * "project_id: 6f2a…, assigneeIds: [c81b…]" cannot, and a confirmation step
 * nobody can actually read is not a confirmation step.
 */

export type AssistantPreview = {
  /** What is being proposed, in a few words. */
  heading: string;
  rows: { label: string; value: string }[];
};

type Speaker = Pick<Translator, "t" | "tag" | "timeZone">;

export function previewOf(
  action: AssistantAction,
  snapshot: AssistantSnapshot,
  i18n: Speaker,
): AssistantPreview | null {
  const { t, tag, timeZone } = i18n;
  const args = action.arguments;

  const text = (key: string) =>
    typeof args[key] === "string" ? (args[key] as string) : null;

  const taskTitle = (id: string | null) =>
    snapshot.tasks.find((task) => task.id === id)?.title ?? null;

  const when = (iso: string | null | undefined) =>
    iso ? formatDateTime(iso, tag, timeZone) : null;

  const row = (label: string, value: string | null | undefined) =>
    value ? [{ label, value }] : [];

  // "Sara, Omar and Lina" in English; "سارة وعمر ولينا" in Arabic. Joining on a
  // literal comma got the separator wrong in one language whichever one it was.
  const list = (names: string[]) =>
    new Intl.ListFormat(tag, { style: "long", type: "conjunction" }).format(names);

  switch (action.name) {
    case "create_task": {
      const title = text("title");
      if (!title) return null;

      const projectId = text("projectId");
      const ids = Array.isArray(args.assigneeIds) ? args.assigneeIds : [];
      const people = ids
        .map((id) => snapshot.team.find((person) => person.id === id)?.name)
        .filter((name): name is string => Boolean(name));

      const status = text("status") as TaskStatus | null;
      const priority = text("priority") as TaskPriority | null;

      return {
        heading: t("assistant.proposeCreate"),
        rows: [
          { label: t("task.fieldTitle"), value: title },
          ...row(t("task.description"), text("description")),
          {
            label: t("sort.project"),
            value:
              snapshot.projects.find((project) => project.id === projectId)?.name ??
              t("common.general"),
          },
          {
            label: t("table.assignees"),
            value: people.length ? list(people) : t("filter.unassigned"),
          },
          ...row(t("meta.dueDate"), when(text("dueAt"))),
          ...row(t("sort.priority"), priority ? t(priorityMeta(priority).label) : null),
          ...row(t("sort.status"), status ? t(statusMeta(status).label) : null),
        ],
      };
    }

    case "set_task_status": {
      const title = taskTitle(text("taskId"));
      const status = text("status") as TaskStatus | null;
      if (!title || !status) return null;

      return {
        heading: t("assistant.proposeStatus"),
        rows: [
          { label: t("table.task"), value: title },
          { label: t("sort.status"), value: t(statusMeta(status).label) },
        ],
      };
    }

    case "reschedule_task": {
      const title = taskTitle(text("taskId"));
      if (!title) return null;
      const due = when(text("dueAt"));

      return {
        heading: t("assistant.proposeReschedule"),
        rows: [
          { label: t("table.task"), value: title },
          { label: t("meta.dueDate"), value: due ?? t("resched.noDueDate") },
        ],
      };
    }

    default:
      return null;
  }
}
