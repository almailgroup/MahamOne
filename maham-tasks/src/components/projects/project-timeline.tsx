"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import {
  Check,
  Clock,
  Flag,
  Loader2,
  MoreHorizontal,
  Pencil,
  Plus,
  RotateCcw,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { DueDate, StatusBadge } from "@/components/tasks/task-meta";
import { TimelineChart } from "@/components/projects/timeline-chart";
import {
  createMilestone,
  deleteMilestone,
  setMilestoneReached,
  updateMilestone,
} from "@/lib/data/milestone-actions";
import { useI18n } from "@/lib/i18n/client";
import {
  layoutTimeline,
  milestoneProgress,
  milestoneState,
  officeDay,
  sortMilestones,
} from "@/lib/timeline";
import type { ProjectMilestone, TaskWithAssignees } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

/**
 * A project laid out against the calendar: its milestones, the work under
 * each, and how far along each one is.
 *
 * Planners set the milestones here and put tasks under them from the task
 * itself. The chart shows only what the filters let through; the progress on
 * each milestone always counts all of its work, so filtering by one person
 * does not make a milestone look further along than it is.
 */
export function ProjectTimeline({
  projectId,
  milestones,
  tasks,
  allTasks,
  canPlan,
  onOpenTask,
  onCreateTask,
}: {
  projectId: string;
  /** Null until migration 44 has been run. */
  milestones: ProjectMilestone[] | null;
  tasks: TaskWithAssignees[];
  allTasks: TaskWithAssignees[];
  canPlan: boolean;
  onOpenTask: (task: TaskWithAssignees) => void;
  onCreateTask: (milestoneId: string) => void;
}) {
  const { t } = useI18n();
  const [adding, setAdding] = React.useState(false);

  const layout = React.useMemo(
    () => layoutTimeline(milestones ?? [], tasks),
    [milestones, tasks],
  );

  const showMilestone = (id: string) => {
    const card = document.getElementById(`milestone-${id}`);
    card?.scrollIntoView({ behavior: "smooth", block: "center" });
    card?.focus({ preventScroll: true });
  };

  const known = new Set((milestones ?? []).map((milestone) => milestone.id));
  const loose = tasks.filter(
    (task) => task.status !== "done" && !(task.milestone_id && known.has(task.milestone_id)),
  );

  return (
    <div className="flex flex-col gap-4">
      {milestones === null && (
        <p className="rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-500">
          {t("milestone.notYet")}
        </p>
      )}

      {milestones !== null && canPlan && (
        <div className="flex justify-end">
          {adding ? (
            <MilestoneForm
              projectId={projectId}
              onDone={() => setAdding(false)}
            />
          ) : (
            <Button size="sm" variant="outline" onClick={() => setAdding(true)}>
              <Flag />
              {t("milestone.add")}
            </Button>
          )}
        </div>
      )}

      {layout.lanes.length > 0 && (
        <TimelineChart layout={layout} onOpenTask={onOpenTask} onShowMilestone={showMilestone} />
      )}

      {milestones !== null && milestones.length === 0 && (
        <EmptyState
          compact
          className="border border-slate-200 bg-surface shadow-xs"
          icon={<Flag />}
          title={t("milestone.emptyTitle")}
          description={t(canPlan ? "milestone.emptyPlanner" : "milestone.emptyMember")}
        />
      )}

      {milestones !== null && milestones.length > 0 && (
        <ol className="stagger grid gap-3 lg:grid-cols-2" aria-label={t("milestone.listLabel")}>
          {sortMilestones(milestones).map((milestone) => (
            <MilestoneCard
              key={milestone.id}
              projectId={projectId}
              milestone={milestone}
              tasks={tasks.filter((task) => task.milestone_id === milestone.id)}
              progress={milestoneProgress(milestone.id, allTasks)}
              canPlan={canPlan}
              onOpenTask={onOpenTask}
              onCreateTask={() => onCreateTask(milestone.id)}
            />
          ))}
        </ol>
      )}

      {milestones !== null && milestones.length > 0 && loose.length > 0 && (
        <section
          aria-label={t("timeline.loose")}
          className="flex flex-col gap-2 rounded-xl border border-slate-200 bg-slate-50 p-4 sm:p-5"
        >
          <h3 className="text-sm font-semibold text-slate-900">
            {t("timeline.loose")}
            <span className="ms-2 text-xs font-medium tabular-nums text-slate-500">{loose.length}</span>
          </h3>
          <p className="text-xs text-slate-500">
            {t(canPlan ? "timeline.looseHintPlanner" : "timeline.looseHint")}
          </p>
          <TaskRows tasks={loose} onOpenTask={onOpenTask} />
        </section>
      )}
    </div>
  );
}

/** Adding one, or renaming and re-dating one. */
function MilestoneForm({
  projectId,
  milestone,
  onDone,
}: {
  projectId: string;
  milestone?: ProjectMilestone;
  onDone: () => void;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const [title, setTitle] = React.useState(milestone?.title ?? "");
  const [dueOn, setDueOn] = React.useState(milestone?.due_on ?? "");
  const [pending, startTransition] = React.useTransition();

  const save = (event: React.FormEvent) => {
    event.preventDefault();
    startTransition(async () => {
      const outcome = milestone
        ? await updateMilestone(milestone.id, projectId, { title, dueOn })
        : await createMilestone(projectId, { title, dueOn });
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      if (!milestone) toast.success(t("milestone.added", { title: title.trim() }));
      onDone();
      router.refresh();
    });
  };

  return (
    <form
      onSubmit={save}
      className="flex w-full flex-col gap-2 rounded-lg border border-slate-200 bg-slate-50 p-2.5 sm:flex-row sm:items-center"
      aria-label={milestone ? t("milestone.edit", { title: milestone.title }) : t("milestone.add")}
    >
      <Input
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        placeholder={t("milestone.titlePlaceholder")}
        aria-label={t("milestone.name")}
        maxLength={120}
        autoFocus
        className="h-9 sm:flex-1"
      />
      <Input
        type="date"
        value={dueOn}
        onChange={(event) => setDueOn(event.target.value)}
        aria-label={t("milestone.date")}
        className="h-9 sm:w-44"
      />
      <div className="flex gap-1.5 self-end sm:self-auto">
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? <Loader2 className="animate-spin" /> : <Check />}
          {milestone ? t("common.save") : t("milestone.addShort")}
        </Button>
        <Button type="button" size="icon-sm" variant="ghost" onClick={onDone} aria-label={t("common.cancel")}>
          <X />
        </Button>
      </div>
    </form>
  );
}

function MilestoneCard({
  projectId,
  milestone,
  tasks,
  progress,
  canPlan,
  onOpenTask,
  onCreateTask,
}: {
  projectId: string;
  milestone: ProjectMilestone;
  tasks: TaskWithAssignees[];
  progress: { done: number; total: number };
  canPlan: boolean;
  onOpenTask: (task: TaskWithAssignees) => void;
  onCreateTask: () => void;
}) {
  const router = useRouter();
  const { t, tn, tm, tag } = useI18n();
  const [editing, setEditing] = React.useState(false);
  const [removing, setRemoving] = React.useState(false);
  const [pending, startTransition] = React.useTransition();

  const { state, daysLeft } = milestoneState(milestone, officeDay(new Date()));
  const date = new Date(`${milestone.due_on}T12:00:00Z`).toLocaleDateString(tag, {
    timeZone: "UTC",
    weekday: "short",
    day: "numeric",
    month: "short",
  });
  const percent = progress.total === 0 ? 0 : Math.round((progress.done / progress.total) * 100);

  const reach = (reached: boolean) =>
    startTransition(async () => {
      const outcome = await setMilestoneReached(milestone.id, projectId, reached);
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      if (reached) toast.success(t("milestone.reachedToast", { title: milestone.title }));
      router.refresh();
    });

  const remove = async () => {
    const outcome = await deleteMilestone(milestone.id, projectId);
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    setRemoving(false);
    router.refresh();
  };

  const ordered = [...tasks].sort(
    (a, b) =>
      Number(a.status === "done") - Number(b.status === "done") ||
      (a.due_at ?? "9999").localeCompare(b.due_at ?? "9999"),
  );

  return (
    <li
      id={`milestone-${milestone.id}`}
      tabIndex={-1}
      className="flex scroll-mt-24 flex-col gap-3 rounded-xl border border-slate-200 bg-surface p-4 shadow-xs outline-none focus-visible:border-primary-300 focus-visible:shadow-md sm:p-5"
    >
      {editing ? (
        <MilestoneForm projectId={projectId} milestone={milestone} onDone={() => setEditing(false)} />
      ) : (
        <div className="flex items-start gap-3">
          <span
            aria-hidden
            className={cn(
              "flex size-9 shrink-0 items-center justify-center rounded-lg [&_svg]:size-4",
              state === "late"
                ? "bg-warning-surface text-warning"
                : state === "reached"
                  ? "bg-primary-solid text-on-primary"
                  : "bg-primary-50 text-primary-600",
            )}
          >
            {state === "reached" ? <Check strokeWidth={3} /> : <Flag />}
          </span>

          <div className="min-w-0 flex-1">
            <h3 className="text-sm font-semibold leading-snug text-slate-900">{milestone.title}</h3>
            <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
              <span className="tabular-nums text-slate-500">{date}</span>
              {state === "late" ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-warning-surface px-2 py-0.5 font-medium text-warning ring-1 ring-inset ring-warning-border">
                  <Clock className="size-3" aria-hidden />
                  {tn("milestone.daysLate", -daysLeft)}
                </span>
              ) : state === "reached" ? (
                <span className="font-medium text-primary-700">{t("milestone.reached")}</span>
              ) : (
                <span className="text-slate-500">
                  {daysLeft === 0 ? t("milestone.dueToday") : tn("milestone.daysLeft", daysLeft)}
                </span>
              )}
            </p>
          </div>

          {canPlan && (
            <div className="flex shrink-0 items-center gap-0.5">
              {state !== "reached" && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => reach(true)}
                  disabled={pending}
                  aria-label={t("milestone.markReachedNamed", { title: milestone.title })}
                  className="max-sm:size-8 max-sm:px-0"
                >
                  {pending ? <Loader2 className="animate-spin" /> : <Check />}
                  {/* The word goes on a phone, where the title needs the width. */}
                  <span className="max-sm:hidden">{t("milestone.markReached")}</span>
                </Button>
              )}
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={t("milestone.actions", { title: milestone.title })}
                  >
                    <MoreHorizontal />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onSelect={onCreateTask}>
                    <Plus />
                    {t("milestone.addTask")}
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => setEditing(true)}>
                    <Pencil />
                    {t("milestone.editShort")}
                  </DropdownMenuItem>
                  {state === "reached" && (
                    <DropdownMenuItem onSelect={() => reach(false)}>
                      <RotateCcw />
                      {t("milestone.reopen")}
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onSelect={() => setRemoving(true)}>
                    <Trash2 />
                    {t("milestone.delete")}
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          )}
        </div>
      )}

      <div className="flex flex-col gap-1.5">
        <div
          role="meter"
          aria-valuemin={0}
          aria-valuemax={progress.total}
          aria-valuenow={progress.done}
          aria-label={t("milestone.progressLabel", {
            title: milestone.title,
            done: progress.done,
            total: progress.total,
          })}
          className="h-2 overflow-hidden rounded-full bg-slate-100"
        >
          <div
            className="h-full rounded-full bg-primary-solid transition-[width] duration-500"
            style={{ width: `${percent}%` }}
          />
        </div>
        <p className="text-xs tabular-nums text-slate-500">
          {progress.total === 0
            ? t("milestone.noTasks")
            : t("milestone.progress", { done: progress.done, total: progress.total })}
        </p>
      </div>

      {ordered.length > 0 && <TaskRows tasks={ordered} onOpenTask={onOpenTask} />}

      <ConfirmDialog
        open={removing}
        onOpenChange={setRemoving}
        title={t("milestone.deleteTitle")}
        description={t("milestone.deleteBody", { title: milestone.title })}
        confirmLabel={t("milestone.delete")}
        onConfirm={remove}
      />
    </li>
  );
}

function TaskRows({
  tasks,
  onOpenTask,
}: {
  tasks: TaskWithAssignees[];
  onOpenTask: (task: TaskWithAssignees) => void;
}) {
  return (
    <ul className="flex flex-col gap-1">
      {tasks.map((task) => (
        <li key={task.id}>
          <button
            type="button"
            onClick={() => onOpenTask(task)}
            // White rows with an edge: they sit on a milestone's white card and
            // on the grey "not under a milestone" box alike.
            className="flex w-full items-center gap-2 rounded-lg bg-surface px-3.5 py-2 text-start ring-1 ring-inset ring-slate-200 transition-colors hover:bg-slate-50"
          >
            <span
              className={cn(
                "min-w-0 flex-1 truncate text-sm text-slate-800",
                task.status === "done" && "text-slate-500 line-through",
              )}
            >
              {task.title}
            </span>
            <DueDate dueAt={task.due_at} status={task.status} className="hidden shrink-0 sm:inline-flex" />
            <StatusBadge status={task.status} />
          </button>
        </li>
      ))}
    </ul>
  );
}
