"use client";

import {
  CalendarDays,
  Clock3,
  Hourglass,
  ListChecks,
  Repeat,
} from "lucide-react";

import {
  Avatar,
  AvatarFallback,
  AvatarImage,
} from "@/components/ui/avatar";
import { initialsFrom } from "@/lib/initials";
import { Badge } from "@/components/ui/badge";
import { priorityMeta, statusMeta } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { formatDateTime, isOverdue } from "@/lib/dates";
import { useI18n } from "@/lib/i18n/client";
import type { TranslationKey } from "@/lib/i18n";
import type {
  Profile,
  RepeatUnit,
  TaskPriority,
  TaskStatus,
} from "@/lib/supabase/database.types";

/** Status pill. Weight, not hue, carries the meaning. */
export function StatusBadge({ status }: { status: TaskStatus }) {
  const { t } = useI18n();
  const meta = statusMeta(status);
  return <Badge variant={meta.variant}>{t(meta.label)}</Badge>;
}

/**
 * Four-bar severity ramp. Colourless by design: filled bars count up with
 * priority, and the label is exposed to assistive tech.
 */
export function PriorityIndicator({
  priority,
  showLabel = false,
}: {
  priority: TaskPriority;
  showLabel?: boolean;
}) {
  const { t } = useI18n();
  const meta = priorityMeta(priority);
  const urgent = priority === "urgent";
  const label = t(meta.label);

  return (
    <span
      className="inline-flex items-center gap-1.5"
      title={t("meta.priorityTitle", { label })}
    >
      <span className="flex items-end gap-0.5" aria-hidden>
        {[1, 2, 3, 4].map((bar) => (
          <span
            key={bar}
            className={cn(
              "w-0.5 rounded-[1px]",
              bar === 1 && "h-1.5",
              bar === 2 && "h-2",
              bar === 3 && "h-2.5",
              bar === 4 && "h-3",
              bar <= meta.weight
                ? urgent
                  ? "bg-warning-marker"
                  : "bg-foreground"
                : "bg-border",
            )}
          />
        ))}
      </span>
      <span
        className={
          showLabel
            ? cn("text-xs", urgent ? "font-medium text-warning" : "text-muted-foreground")
            : "sr-only"
        }
      >
        {label}
      </span>
    </span>
  );
}

/** Formats a yyyy-mm-dd date, marking anything overdue on an unfinished task. */
/**
 * That a task comes back.
 *
 * An icon rather than a sentence: on a card this sits beside the date and
 * the status, where a line of prose would crowd out the title. The sentence
 * is the title attribute and the screen-reader text, so nothing is lost —
 * and it says "monthly" rather than "every 1 months", which is how people
 * write it and how the dialog offers it.
 */
export function RepeatBadge({
  every,
  interval,
  className,
}: {
  every: RepeatUnit | null;
  interval: number;
  className?: string;
}) {
  const { t } = useI18n();
  if (!every) return null;

  const plain: Record<RepeatUnit, TranslationKey> = {
    day: "task.repeatsDaily",
    week: "task.repeatsWeekly",
    month: "task.repeatsMonthly",
    year: "task.repeatsYearly",
  };
  const label =
    interval === 1
      ? t(plain[every])
      : t("task.repeatsEvery", {
          n: interval,
          unit: t(`task.repeatUnit.${every}` as TranslationKey),
        });

  return (
    <span
      className={cn("inline-flex items-center gap-1 text-xs text-muted-foreground", className)}
      title={label}
    >
      <Repeat className="size-3" />
      <span className="sr-only">{label}</span>
    </span>
  );
}

/**
 * How far along a task's steps are.
 *
 * A count rather than a bar: "3/5" is read at a glance and takes the width
 * of a word, and a bar two millimetres long on a phone says nothing a number
 * does not. Hidden when a task has no steps, which is most of them.
 */
export function ChecklistProgressBadge({
  progress,
  className,
}: {
  progress: { done: number; total: number };
  className?: string;
}) {
  const { t } = useI18n();
  if (progress.total === 0) return null;

  const complete = progress.done === progress.total;

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 text-xs tabular-nums",
        complete ? "text-foreground" : "text-muted-foreground",
        className,
      )}
      title={t("checklist.progress", { done: progress.done, total: progress.total })}
    >
      <ListChecks className="size-3" />
      {progress.done}/{progress.total}
    </span>
  );
}

export function DueDate({
  dueAt,
  status,
  className,
}: {
  dueAt: string | null;
  status: TaskStatus;
  className?: string;
}) {
  const { t, tag, timeZone } = useI18n();
  if (!dueAt) return null;

  const overdue = isOverdue(dueAt, status);

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 text-xs",
        overdue
          // The one place colour is allowed. A dotted underline was easy to
          // scan straight past on a board full of dates.
          ? "rounded-full bg-warning-surface px-2.5 py-0.5 font-semibold text-warning"
          : "text-muted-foreground",
        className,
      )}
      title={overdue ? t("meta.overdue") : t("meta.dueDate")}
    >
      <CalendarDays className="size-3" />
      {formatDateTime(dueAt, tag, timeZone)}
      {overdue && <span className="sr-only">{t("meta.overdueSr")}</span>}
    </span>
  );
}

/** Overlapping avatar stack, capped so long assignee lists stay compact. */
export function AssigneeStack({
  assignees,
  max = 3,
  className,
}: {
  assignees: Profile[];
  max?: number;
  /** Lets a caller drop the faces where the row needs the width more. */
  className?: string;
}) {
  if (assignees.length === 0) return null;

  const shown = assignees.slice(0, max);
  const overflow = assignees.length - shown.length;

  return (
    <span className={cn("flex items-center -space-x-1.5", className)}>
      {shown.map((person) => (
        <Avatar
          key={person.id}
          className="size-5 ring-1 ring-background"
          title={person.full_name ?? person.email}
        >
          {person.avatar_url && <AvatarImage src={person.avatar_url} alt="" />}
          <AvatarFallback className="text-[9px]">
            {initialsFrom(person.full_name, person.email)}
          </AvatarFallback>
        </Avatar>
      ))}
      {overflow > 0 && (
        <span className="flex size-5 items-center justify-center rounded-full bg-muted text-[9px] font-medium text-muted-foreground ring-1 ring-background">
          +{overflow}
        </span>
      )}
    </span>
  );
}

/**
 * Who opened this task and when.
 *
 * `creator` is resolved from the team roster rather than joined onto the task:
 * every signed-in user can read every profile, so the lookup always succeeds
 * for an account that still exists. A null creator means the account was
 * removed — created_by is ON DELETE SET NULL — and the timestamp still stands.
 */
export function TaskProvenance({
  createdAt,
  creator,
}: {
  createdAt: string;
  creator: Profile | null;
}) {
  const { t, tag, timeZone } = useI18n();
  const name = creator?.full_name ?? creator?.email ?? null;

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-xl bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
      <span className="inline-flex min-w-0 items-center gap-1.5">
        <Avatar className="size-5">
          {creator?.avatar_url && <AvatarImage src={creator.avatar_url} alt="" />}
          <AvatarFallback className="text-[9px]">
            {initialsFrom(creator?.full_name, creator?.email)}
          </AvatarFallback>
        </Avatar>
        <span className="truncate">
          {t("meta.createdBy")}{" "}
          {name ? (
            <span className="font-medium text-foreground">{name}</span>
          ) : (
            <span className="italic">{t("meta.removedAccount")}</span>
          )}
          {creator?.job_title && <> · {creator.job_title}</>}
        </span>
      </span>

      <span className="inline-flex items-center gap-1.5">
        <Clock3 className="size-3.5 shrink-0" />
        <time
          dateTime={createdAt}
          title={new Date(createdAt).toLocaleString(tag, { timeZone })}
        >
          {formatDateTime(createdAt, tag, timeZone)}
        </time>
      </span>
    </div>
  );
}

/**
 * Shown while a task waits on others that are still open. Muted, not amber:
 * waiting is a state of the plan, not lateness.
 */
export function WaitingBadge({
  count,
  status,
  className,
}: {
  count: number;
  status: TaskStatus;
  className?: string;
}) {
  const { t, tn } = useI18n();
  if (count === 0 || status === "done") return null;

  return (
    <span
      className={cn("inline-flex items-center gap-1 text-xs text-muted-foreground", className)}
      title={tn("dependency.waitingOnCount", count)}
    >
      <Hourglass className="size-3" aria-hidden />
      {t("dependency.waiting")}
    </span>
  );
}
