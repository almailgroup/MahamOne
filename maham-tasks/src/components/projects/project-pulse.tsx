"use client";

import { ProgressBar } from "@/components/dashboard/metric-card";
import { useI18n } from "@/lib/i18n/client";
import { isOverdue } from "@/lib/dates";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * One line that says how the project is going.
 *
 * Opening a project used to show a board and nothing else: how far along it
 * is, and whether anything has slipped, had to be worked out by counting
 * cards. Now it is the first thing under the title.
 */
export function ProjectPulse({ tasks }: { tasks: TaskWithAssignees[] }) {
  const { t } = useI18n();
  const total = tasks.length;
  if (total === 0) return null;

  const done = tasks.filter((task) => task.status === "done").length;
  const inReview = tasks.filter((task) => task.status === "in_review").length;
  const overdue = tasks.filter((task) => isOverdue(task.due_at, task.status)).length;
  const percent = Math.round((done / total) * 100);

  const parts = [
    t("common.doneOf", { done, total }),
    inReview > 0 && t("pulse.awaiting", { n: inReview }),
    overdue > 0 && t("dash.overdueCount", { n: overdue }),
  ].filter(Boolean);

  return (
    <div className="flex flex-col gap-1.5 rounded-[1.75rem] bg-card px-5 py-3.5 shadow-[var(--shadow-xs)]">
      <div className="flex items-center justify-between gap-3 text-xs">
        <span className="text-muted-foreground">{parts.join(" · ")}</span>
        <span className="font-medium tabular-nums">{percent}%</span>
      </div>
      <ProgressBar value={percent} label={t("pulse.label", { n: percent })} />
    </div>
  );
}
