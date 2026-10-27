"use client";

import { initialsFrom } from "@/lib/initials";
import { priorityMeta, statusMeta, TASK_PRIORITIES, TASK_STATUSES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import type { Translator } from "@/lib/i18n";
import type {
  TaskActivityAction,
  TaskActivityWithActor,
  TaskPriority,
  TaskStatus,
} from "@/lib/supabase/database.types";

/** Human-readable line for one audit row. */
function describe(entry: TaskActivityWithActor, t: Translator["t"]): string {
  const to = (value: string | null) =>
    value ? readableStatus(value, t) : t("activity.nothing");
  const priority = (value: string | null) =>
    value ? readablePriority(value, t) : t("activity.none");

  switch (entry.action satisfies TaskActivityAction) {
    case "created":
      return t("activity.created");
    case "status_changed":
      return t("activity.statusChanged", { from: to(entry.old_value), to: to(entry.new_value) });
    case "priority_changed":
      return t("activity.priorityChanged", {
        from: priority(entry.old_value),
        to: priority(entry.new_value),
      });
    case "follow_up_set":
      return t("activity.followUpSet", { when: entry.new_value ?? t("activity.later") });
    case "follow_up_cleared":
      return t("activity.followUpCleared");
    case "due_date_changed":
      return entry.new_value
        ? t("activity.dueSet", { when: entry.new_value })
        : t("activity.dueCleared");
    case "assignee_added":
      return t("activity.assigned", { who: entry.new_value ?? t("activity.someone") });
    case "assignee_removed":
      return t("activity.unassigned", { who: entry.old_value ?? t("activity.someone") });
    case "commented":
      return t("activity.commented");
    case "deleted":
      return t("activity.deleted");
    case "restored":
      return t("activity.restored");
    case "updated":
      return entry.field === "description"
        ? t("activity.descriptionUpdated")
        : t("activity.renamed", { title: entry.new_value ?? "" });
    default:
      return t("activity.updated");
  }
}

/** Status values are stored as enum keys; show the label people recognise. */
function readableStatus(value: string, t: Translator["t"]): string {
  return TASK_STATUSES.some((status) => status.value === value)
    ? t(statusMeta(value as TaskStatus).label)
    : value;
}

function readablePriority(value: string, t: Translator["t"]): string {
  return TASK_PRIORITIES.some((priority) => priority.value === value)
    ? t(priorityMeta(value as TaskPriority).label)
    : value;
}

function relativeTime(iso: string, t: Translator["t"], tag: Translator["tag"]): string {
  const then = new Date(iso).getTime();
  const seconds = Math.round((Date.now() - then) / 1000);

  if (seconds < 60) return t("common.justNow");
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return t("common.minutesAgo", { n: minutes });
  const hours = Math.round(minutes / 60);
  if (hours < 24) return t("common.hoursAgo", { n: hours });
  const days = Math.round(hours / 24);
  if (days < 30) return t("common.daysAgo", { n: days });

  return new Date(iso).toLocaleDateString(tag, {
    day: "numeric",
    month: "short",
  });
}

export function ActivityLog({
  entries,
}: {
  entries: TaskActivityWithActor[];
}) {
  const { t, tag } = useI18n();

  if (entries.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">{t("activity.empty")}</p>
    );
  }

  return (
    <ol className="flex flex-col gap-2.5">
      {entries.map((entry) => {
        const actor = entry.actor;
        const name = actor?.full_name ?? actor?.email ?? t("common.someone");

        return (
          <li key={entry.id} className="flex items-start gap-2 text-sm">
            <span
              className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-muted text-[9px] font-medium text-muted-foreground"
              aria-hidden
            >
              {initialsFrom(actor?.full_name, actor?.email)}
            </span>
            <p className="leading-snug text-muted-foreground">
              <span className="font-medium text-foreground">{name}</span>{" "}
              {describe(entry, t)}
              <span className="ms-1.5 whitespace-nowrap text-xs">
                {relativeTime(entry.created_at, t, tag)}
              </span>
            </p>
          </li>
        );
      })}
    </ol>
  );
}
