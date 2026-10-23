"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, ArrowUpDown, CloudUpload, ListFilter } from "lucide-react";
import { toast } from "sonner";

import { BulkActionBar } from "@/components/tasks/bulk-action-bar";
import { RescheduleMenu } from "@/components/tasks/reschedule-menu";
import { SwipeCard } from "@/components/tasks/swipe-card";
import { useOutbox } from "@/components/offline/outbox-provider";
import { withPending } from "@/lib/outbox";
import { Checkbox } from "@/components/ui/checkbox";
import { EmptyState } from "@/components/ui/empty-state";
import { deleteTask, moveTask, restoreTask } from "@/lib/data/task-actions";
import type { TaskStatus } from "@/lib/supabase/database.types";
import {
  AssigneeStack,
  DueDate,
  PriorityIndicator,
  ChecklistProgressBadge,
  WaitingBadge,
  RepeatBadge,
} from "@/components/tasks/task-meta";
import { StatusBadge } from "@/components/tasks/task-meta";
import { statusMeta } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import {
  nextSort,
  sortTasks,
  type TaskSort,
  type TaskSortKey,
} from "@/lib/task-filters";
import { cn } from "@/lib/utils";
import { LabelPills } from "@/components/labels/label-pills";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * Filterable list view.
 *
 * A real <table> on desktop for scannability and correct semantics; stacked
 * rows below `md`, where a four-column table would be unreadable.
 */
export function TaskTable({
  tasks,
  onOpenTask,
  projectId = null,
  canComplete = false,
  canDelete = false,
  projectName,
  canReschedule = false,
  emptyState,
  sort,
  onSortChange,
}: {
  tasks: TaskWithAssignees[];
  onOpenTask: (task: TaskWithAssignees) => void;
  projectId?: string | null;
  /** Whether the viewer may move tasks into Done. */
  canComplete?: boolean;
  /** Whether the viewer may delete tasks. Members may not. */
  canDelete?: boolean;
  /**
   * Supplied by the cross-project views, which need to say which project a
   * task belongs to. Inside a single project it would be the same word on
   * every row, so it is left out there.
   */
  projectName?: (projectId: string | null) => string;
  /** Shows the quick date control on each row. Managers only. */
  canReschedule?: boolean;
  /** Overrides the default "no matches" panel. */
  emptyState?: React.ReactNode;
  /**
   * The order, held by the page rather than here: on a phone the control
   * that changes it sits in the page's own search row (see TaskSortMenu),
   * and the desktop column headings have to agree with it. No sort is a
   * state, and keeps the board's own order.
   */
  sort: TaskSort | null;
  onSortChange: (sort: TaskSort | null) => void;
}) {
  const router = useRouter();
  const { t, tn } = useI18n();
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  const { pending } = useOutbox();

  // Changes made with no signal show as made, not as they were.
  const rows = React.useMemo(
    () => sortTasks(withPending(tasks, pending), sort, projectName),
    [tasks, pending, sort, projectName],
  );
  const unsent = React.useMemo(
    () => new Set(withPending(tasks, pending).filter((task) => task.unsent).map((task) => task.id)),
    [tasks, pending],
  );

  /** Click a column: sort by it, click again to flip, a third time to clear. */
  const toggleSort = (key: TaskSortKey) => onSortChange(nextSort(sort, key));

  // Selecting is only offered to people who can act on a selection.
  const selectable = canComplete || canDelete;
  const visibleIds = React.useMemo(() => tasks.map((t) => t.id), [tasks]);

  // Drop anything that has filtered out from under the selection, so the
  // count never claims more than is on screen.
  React.useEffect(() => {
    setSelected((current) => {
      const next = new Set([...current].filter((id) => visibleIds.includes(id)));
      return next.size === current.size ? current : next;
    });
  }, [visibleIds]);

  const allSelected = tasks.length > 0 && selected.size === tasks.length;

  const toggle = (id: string) =>
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const chosen = () => tasks.filter((task) => selected.has(task.id));

  async function bulkMove(status: TaskStatus) {
    const batch = chosen();
    // Positions are spaced so the moved tasks keep their relative order at
    // the end of the target column.
    const results = await Promise.all(
      batch.map((task, index) =>
        moveTask(task.id, task.project_id ?? projectId, status, Date.now() + index),
      ),
    );
    const failed = results.filter((r) => !r.ok).length;
    report(batch.length - failed, failed, (tasks) =>
      t("table.movedTo", { tasks, status: t(statusMeta(status).label) }),
    );
    setSelected(new Set());
    router.refresh();
  }

  async function bulkDelete() {
    const batch = chosen();
    const results = await Promise.all(
      batch.map((task) => deleteTask(task.id, task.project_id ?? projectId)),
    );
    const done = batch.filter((_, index) => results[index].ok);
    const failed = batch.length - done.length;
    report(done.length, failed, (tasks) => t("table.deleted", { tasks }), async () => {
      const back = await Promise.all(
        done.map((task) => restoreTask(task.id, task.project_id ?? projectId)),
      );
      const lost = back.filter((r) => !r.ok).length;
      if (lost > 0) toast.error(t("table.restoredFailed", { n: lost }));
      else toast.success(t("table.restored", { tasks: tn("count.tasks", done.length) }));
      router.refresh();
    });
    setSelected(new Set());
    router.refresh();
  }

  function report(
    done: number,
    failed: number,
    describe: (tasks: string) => string,
    undo?: () => Promise<void>,
  ) {
    if (done > 0) {
      toast.success(
        describe(tn("count.tasks", done)),
        // A delete is undoable for ten seconds; the bin keeps it for a month.
        undo
          ? { duration: 10_000, action: { label: t("common.undo"), onClick: () => void undo() } }
          : undefined,
      );
    }
    // Partial failure is the interesting case: RLS may refuse some of a
    // selection and allow the rest, and silence there would be a lie.
    if (failed > 0) {
      toast.error(t("table.partialFail", { tasks: tn("count.tasks", failed) }));
    }
  }
  if (tasks.length === 0) {
    return (
      emptyState ?? (
        <EmptyState
          icon={<ListFilter />}
          title={t("table.noMatch")}
          description={t("table.noMatchBody")}
        />
      )
    );
  }

  return (
    <>
      {/* Desktop */}
      {/* No rules between rows: each row is its own rounded band, told
          apart by spacing and a faint alternating tint, and it lights up as
          a pill under the pointer. */}
      <div className="hidden overflow-hidden rounded-3xl bg-card p-2 shadow-[var(--shadow-sm)] md:block">
        <table className="w-full border-separate border-spacing-0 text-sm">
          <thead>
            <tr className="text-start">
              {selectable && (
                <Th className="w-10">
                  <Checkbox
                    checked={allSelected}
                    onCheckedChange={() =>
                      setSelected(allSelected ? new Set() : new Set(visibleIds))
                    }
                    aria-label={allSelected ? t("bulk.clearSelection") : t("table.selectAll")}
                  />
                </Th>
              )}
              <SortTh column="title" sort={sort} onSort={toggleSort} className={projectName ? "w-[34%]" : "w-[45%]"}>
                {t("table.task")}
              </SortTh>
              {projectName && (
                <SortTh column="project" sort={sort} onSort={toggleSort}>
                  {t("sort.project")}
                </SortTh>
              )}
              <SortTh column="status" sort={sort} onSort={toggleSort}>
                {t("sort.status")}
              </SortTh>
              <SortTh column="priority" sort={sort} onSort={toggleSort}>
                {t("sort.priority")}
              </SortTh>
              <SortTh column="due" sort={sort} onSort={toggleSort}>
                {t("table.due")}
              </SortTh>
              <Th className="text-end">{t("table.assignees")}</Th>
              {canReschedule && <Th className="w-10 text-end sr-only">{t("table.moveDate")}</Th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((task) => (
              <tr
                key={task.id}
                onClick={() => onOpenTask(task)}
                className={cn(
                  "cursor-pointer transition-colors even:bg-foreground/[0.025] hover:bg-foreground/[0.06]",
                  "[&>td:first-child]:rounded-s-2xl [&>td:last-child]:rounded-e-2xl",
                  selected.has(task.id) && "bg-primary/[0.08] even:bg-primary/[0.08] hover:bg-primary/[0.11]",
                )}
              >
                {selectable && (
                  <td className="px-4 py-3.5" onClick={(e) => e.stopPropagation()}>
                    <Checkbox
                      checked={selected.has(task.id)}
                      onCheckedChange={() => toggle(task.id)}
                      aria-label={t("table.selectTask", { title: task.title })}
                    />
                  </td>
                )}
                <td className="px-4 py-3.5">
                  <button
                    type="button"
                    className="text-start font-medium focus-visible:outline-none"
                    onClick={(event) => {
                      event.stopPropagation();
                      onOpenTask(task);
                    }}
                  >
                    {task.title}
                  </button>
                  <LabelPills ids={task.labelIds} className="mt-1" />
                </td>
                {projectName && (
                  <td className="px-4 py-3.5 text-muted-foreground">
                    {projectName(task.project_id)}
                  </td>
                )}
                <td className="px-4 py-3.5">
                  <StatusBadge status={task.status} />
                </td>
                <td className="px-4 py-3.5">
                  <PriorityIndicator priority={task.priority} showLabel />
                </td>
                <td className="px-4 py-3.5">
                  <DueDate dueAt={task.due_at} status={task.status} />
                  <RepeatBadge every={task.repeat_every} interval={task.repeat_interval} />
                  <ChecklistProgressBadge progress={task.checklist} />
                  <WaitingBadge count={task.waitingOn} status={task.status} />
                </td>
                <td className="px-4 py-3.5">
                  <div className="flex justify-end">
                    <AssigneeStack assignees={task.assignees} />
                  </div>
                </td>
                {canReschedule && (
                  <td className="px-4 py-3.5" onClick={(e) => e.stopPropagation()}>
                    <div className="flex justify-end">
                      <RescheduleMenu task={task} compact />
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/*
       * Mobile. The checkbox and the reschedule menu used to flank the card,
       * which cost a quarter of a phone's width and left every title wrapping
       * early. They now sit inside it, on a footer line, and the card itself
       * is the tap target — a full-size overlay rather than a wrapper, since
       * a <button> may not contain other controls.
       */}
      <ul className="stagger flex flex-col gap-2 md:hidden">
        {rows.map((task) => {
          const isSelected = selected.has(task.id);

          return (
            <SwipeCard
              key={task.id}
              task={task}
              projectId={projectId}
              canComplete={canComplete}
              canReschedule={canReschedule}
              className={cn(
                "lift relative rounded-[1.75rem] bg-card p-3.5 shadow-[var(--shadow-sm)]",
                // Opaque, unlike a tint: what a swipe reveals sits beneath.
                isSelected &&
                  "bg-[color-mix(in_srgb,var(--primary)_7%,var(--card))] shadow-[var(--shadow-md)]",
              )}
            >
              <button
                type="button"
                onClick={() => onOpenTask(task)}
                aria-label={t("table.openTask", { title: task.title })}
                className="absolute inset-0 rounded-[inherit] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              />

              {/* Passes taps through to the overlay behind it. */}
              <div className="pointer-events-none relative">
                {/* Selecting and rescheduling used to be a footer of their
                    own, below a divider: fifty pixels of chrome on every card
                    for two things used now and then. Rescheduling goes beside
                    the title, which never wraps — put on the meta row it was
                    pushed onto a line of its own the moment a status and a
                    date filled that row. The people go there too, for the
                    same reason: last on the meta row, they wrapped onto a
                    line of their own whenever the row was full. */}
                <div className="flex items-start gap-2">
                  <div className="min-w-0 flex-1">
                    <p className="text-[0.9375rem] font-medium leading-snug">
                      {task.title}
                    </p>
                    {projectName && (
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        {projectName(task.project_id)}
                      </p>
                    )}
                    <LabelPills ids={task.labelIds} className="mt-1.5" />
                  </div>
                  {task.assignees.length > 0 && (
                    <span className="shrink-0 pt-0.5">
                      <AssigneeStack assignees={task.assignees} max={3} />
                    </span>
                  )}
                  {canReschedule && (
                    <span className="pointer-events-auto -me-1.5 -mt-1.5 shrink-0">
                      <RescheduleMenu task={task} compact />
                    </span>
                  )}
                </div>

                <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1.5">
                  {selectable && (
                    <span className="pointer-events-auto flex items-center">
                      <Checkbox
                        checked={isSelected}
                        onCheckedChange={() => toggle(task.id)}
                        aria-label={t("table.selectTask", { title: task.title })}
                      />
                    </span>
                  )}
                  <StatusBadge status={task.status} />
                  <PriorityIndicator priority={task.priority} showLabel />
                  <DueDate dueAt={task.due_at} status={task.status} />
                  <RepeatBadge every={task.repeat_every} interval={task.repeat_interval} />
                  <ChecklistProgressBadge progress={task.checklist} />
                  <WaitingBadge count={task.waitingOn} status={task.status} />
                  {unsent.has(task.id) && (
                    <span
                      className="inline-flex items-center gap-1 text-xs text-muted-foreground"
                      title={t("outbox.waiting")}
                    >
                      <CloudUpload className="size-3.5" aria-hidden />
                      {t("outbox.waiting")}
                    </span>
                  )}
                </div>
              </div>
            </SwipeCard>
          );
        })}
      </ul>

      {selectable && (
        <BulkActionBar
          count={selected.size}
          canComplete={canComplete}
          onMove={bulkMove}
          onDelete={bulkDelete}
          onClear={() => setSelected(new Set())}
        />
      )}
    </>
  );
}

/**
 * A column heading that sorts its column. The arrow only appears on the
 * active column; a resting heading looks like a heading, not like a button.
 */
function SortTh({
  column,
  sort,
  onSort,
  className,
  children,
}: {
  column: TaskSortKey;
  sort: TaskSort | null;
  onSort: (key: TaskSortKey) => void;
  className?: string;
  children: React.ReactNode;
}) {
  const active = sort?.key === column;
  return (
    <th
      scope="col"
      aria-sort={active ? (sort.direction === "asc" ? "ascending" : "descending") : "none"}
      className={cn("px-4 py-2.5 text-xs font-medium text-muted-foreground", className)}
    >
      <button
        type="button"
        onClick={() => onSort(column)}
        className={cn(
          "-mx-1.5 inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 transition-colors hover:text-foreground",
          active && "text-foreground",
        )}
      >
        {children}
        {active ? (
          sort.direction === "asc" ? <ArrowUp className="size-3" /> : <ArrowDown className="size-3" />
        ) : (
          <ArrowUpDown className="size-3 opacity-0 transition-opacity group-hover:opacity-100" aria-hidden />
        )}
      </button>
    </th>
  );
}

function Th({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <th
      scope="col"
      className={`px-4 py-2.5 text-xs font-medium text-muted-foreground ${className ?? ""}`}
    >
      {children}
    </th>
  );
}
