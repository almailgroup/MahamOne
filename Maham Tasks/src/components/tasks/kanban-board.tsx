"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
  MouseSensor,
  TouchSensor,
  closestCorners,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { Plus } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { DragInstructions, TaskCard } from "@/components/tasks/task-card";
import { QuickAddTask } from "@/components/tasks/quick-add-task";
import { StatusMoveMenu } from "@/components/tasks/status-move-menu";
import { useOutbox } from "@/components/offline/outbox-provider";
import { TASK_STATUSES } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";
import type {
  TaskStatus,
  TaskWithAssignees,
} from "@/lib/supabase/database.types";

/** Matches POSITION_STEP in task-actions. */
const POSITION_STEP = 1024;

/**
 * Minimalist Kanban board.
 *
 * Card order is optimistic: the local list is reordered immediately and the
 * single affected row is persisted in the background. If the write is rejected
 * (RLS, or the task moved underneath us) the board is reverted and the user is
 * told.
 */
export function KanbanBoard({
  tasks,
  projectId,
  canComplete,
  canCreate,
  onOpenTask,
  onCreateTask,
}: {
  tasks: TaskWithAssignees[];
  projectId: string | null;
  /** Whether the viewer may move cards into Done. */
  canComplete: boolean;
  /** Whether the viewer may add a task to a column. */
  canCreate: boolean;
  onOpenTask: (task: TaskWithAssignees) => void;
  onCreateTask: (status: TaskStatus) => void;
}) {
  const router = useRouter();
  const { t, tm } = useI18n();
  const { send } = useOutbox();

  /** Persist a move, or keep it on the phone with no signal. */
  const persistMove = (task: TaskWithAssignees, status: TaskStatus, position: number) =>
    send({ kind: "move", taskId: task.id, projectId, status, position, title: task.title });
  const [items, setItems] = React.useState(tasks);
  const [activeId, setActiveId] = React.useState<string | null>(null);

  // Re-sync when the server sends a new list (refresh, realtime, filters).
  React.useEffect(() => setItems(tasks), [tasks]);

  const sensors = useSensors(
    // A small distance threshold keeps a click on the card title from
    // registering as a drag.
    useSensor(MouseSensor, { activationConstraint: { distance: 4 } }),
    // Touch is deliberately a different gesture. A distance threshold cannot
    // work here: on a phone a swipe across a card is how you scroll the board,
    // and a pointer sensor claims that swipe (or the browser cancels the drag
    // mid-way, which is worse). A short press picks the card up instead, and
    // `tolerance` lets a thumb wobble during that press without cancelling it.
    useSensor(TouchSensor, {
      activationConstraint: { delay: 220, tolerance: 8 },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  const columns = React.useMemo(() => {
    const grouped = new Map<TaskStatus, TaskWithAssignees[]>();
    for (const status of TASK_STATUSES) grouped.set(status.value, []);
    for (const task of items) grouped.get(task.status)?.push(task);
    for (const list of grouped.values())
      list.sort((a, b) => a.position - b.position);
    return grouped;
  }, [items]);

  const activeTask = items.find((task) => task.id === activeId) ?? null;

  /**
   * Send a task to the end of another column.
   *
   * Shares the optimistic-update-then-persist path with a drop, including the
   * revert, so a tap and a drag cannot disagree about what happened.
   */
  async function moveToColumn(task: TaskWithAssignees, targetStatus: TaskStatus) {
    if (task.status === targetStatus) return;

    if (!canComplete && (targetStatus === "done" || task.status === "done")) {
      toast.error(
        targetStatus === "done" ? t("kanban.doneGate") : t("kanban.reopenGate"),
      );
      return;
    }

    const column = (columns.get(targetStatus) ?? []).filter(
      (entry) => entry.id !== task.id,
    );
    const position = midpoint(column[column.length - 1]?.position, undefined);

    const previous = items;
    setItems((current) =>
      current.map((entry) =>
        entry.id === task.id
          ? { ...entry, status: targetStatus, position }
          : entry,
      ),
    );

    const outcome = await persistMove(task, targetStatus, position);
    // Kept for later: the card stays where it was put.
    if (outcome === "kept") {
      toast(t("outbox.kept"));
      return;
    }
    if (!outcome.ok) {
      setItems(previous);
      toast.error(tm(outcome.error));
      return;
    }
    router.refresh();
  }

  function onDragStart(event: DragStartEvent) {
    setActiveId(String(event.active.id));
  }

  async function onDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    setActiveId(null);
    if (!over) return;

    const taskId = String(active.id);
    const task = items.find((entry) => entry.id === taskId);
    if (!task) return;

    // Dropping on a column droppable gives a status; dropping on a card gives
    // that card's id, from which the target column is derived.
    const overId = String(over.id);
    const overTask = items.find((entry) => entry.id === overId);
    const targetStatus = (
      overTask ? overTask.status : stripColumnPrefix(overId)
    ) as TaskStatus;

    if (!TASK_STATUSES.some((status) => status.value === targetStatus)) return;

    // The database enforces this too; refusing here keeps the card from
    // visibly jumping into Done and then snapping back.
    if (!canComplete && targetStatus !== task.status) {
      if (targetStatus === "done") {
        toast.error(t("kanban.doneGate"));
        return;
      }
      if (task.status === "done") {
        toast.error(t("kanban.reopenGate"));
        return;
      }
    }

    const column = (columns.get(targetStatus) ?? []).filter(
      (entry) => entry.id !== taskId,
    );

    // Insert before the card we were dropped on, or at the end of the column.
    const dropIndex = overTask
      ? column.findIndex((entry) => entry.id === overTask.id)
      : column.length;
    const index = dropIndex === -1 ? column.length : dropIndex;

    const position = midpoint(
      column[index - 1]?.position,
      column[index]?.position,
    );

    if (task.status === targetStatus && task.position === position) return;

    const previous = items;
    setItems((current) =>
      current.map((entry) =>
        entry.id === taskId
          ? { ...entry, status: targetStatus, position }
          : entry,
      ),
    );

    const outcome = await persistMove(task, targetStatus, position);
    if (outcome === "kept") {
      toast(t("outbox.kept"));
      return;
    }

    if (!outcome.ok) {
      setItems(previous);
      toast.error(tm(outcome.error));
      return;
    }

    router.refresh();
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCorners}
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      onDragCancel={() => setActiveId(null)}
      accessibility={{
        screenReaderInstructions: {
          draggable: t("kanban.srDraggable"),
        },
      }}
    >
      <DragInstructions />

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {TASK_STATUSES.map((status) => {
          const columnTasks = columns.get(status.value) ?? [];

          return (
            <Column
              key={status.value}
              status={status.value}
              label={t(status.label)}
              count={columnTasks.length}
              canCreate={canCreate}
              onCreate={() => onCreateTask(status.value)}
              projectId={projectId}
            >
              <SortableContext
                items={columnTasks.map((task) => task.id)}
                strategy={verticalListSortingStrategy}
              >
                {columnTasks.map((task) => (
                  <SortableCard
                    key={task.id}
                    task={task}
                    onOpen={() => onOpenTask(task)}
                    move={
                      <StatusMoveMenu
                        status={task.status}
                        canComplete={canComplete}
                        onMove={(next) => void moveToColumn(task, next)}
                      />
                    }
                  />
                ))}
              </SortableContext>

              {columnTasks.length === 0 && !canCreate && (
                <p className="rounded-xl bg-foreground/[0.05] px-2 py-6 text-center text-xs text-muted-foreground">
                  {t("kanban.nothingHere")}
                </p>
              )}
            </Column>
          );
        })}
      </div>

      <DragPreview task={activeTask} />
    </DndContext>
  );
}

/**
 * The card that follows the cursor while dragging.
 *
 * Portalled to <body> on purpose. The overlay is `position: fixed`, so any
 * ancestor with a transform, filter or filling transform animation would
 * become its containing block and offset it from the cursor by however far
 * that ancestor sits from the viewport origin. Hanging it off <body> puts it
 * out of reach of whatever the page above it does.
 */
function DragPreview({ task }: { task: TaskWithAssignees | null }) {
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);

  const overlay = (
    <DragOverlay dropAnimation={null}>
      {task && (
        <TaskCard
          task={task}
          className="rotate-1 shadow-[var(--shadow-lg)]"
        />
      )}
    </DragOverlay>
  );

  // No document during SSR, and nothing to drag before hydration anyway.
  return mounted ? createPortal(overlay, document.body) : null;
}

function Column({
  status,
  label,
  count,
  canCreate,
  onCreate,
  projectId,
  children,
}: {
  status: TaskStatus;
  label: string;
  count: number;
  canCreate: boolean;
  /** Opens the full dialog, for a task that needs more than a title. */
  onCreate: () => void;
  projectId: string | null;
  children: React.ReactNode;
}) {
  const { t } = useI18n();
  // Column-level droppable, so an empty column still accepts a card.
  const { setNodeRef, isOver } = useDroppable({ id: `column:${status}` });

  return (
    <section
      ref={setNodeRef}
      aria-label={label}
      className={cn(
        "flex min-h-[10rem] flex-col gap-2 rounded-3xl bg-chrome/60 p-2.5 transition-colors duration-200",
        // The column a card is over glows in the theme's colour and swells a
        // little, so the drop target is plain without drawing a line round it.
        isOver && "bg-primary/[0.08] scale-[1.01]",
      )}
    >
      <header className="flex items-center justify-between gap-2 px-1">
        <div className="flex items-center gap-1.5">
          <h3 className="text-xs font-medium">{label}</h3>
          <span className="text-xs text-muted-foreground">{count}</span>
        </div>
        {canCreate && (
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={onCreate}
            aria-label={t("kanban.addTo", { column: label })}
          >
            <Plus />
          </Button>
        )}
      </header>

      <div className="flex flex-col gap-2">{children}</div>

      {/* Quick capture at the foot of the column; the + in the header still
          opens the full dialog for a task that needs more than a title. */}
      {canCreate && (
        <QuickAddTask projectId={projectId} status={status} className="mt-auto" />
      )}
    </section>
  );
}

function SortableCard({
  task,
  onOpen,
  move,
}: {
  task: TaskWithAssignees;
  onOpen: () => void;
  move?: React.ReactNode;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: task.id });

  return (
    <TaskCard
      ref={setNodeRef}
      task={task}
      onOpen={onOpen}
      move={move}
      dragging={isDragging}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      // Once a press has become a drag the browser must stop treating the
      // gesture as a scroll, or it cancels the pointer stream underneath us.
      className={isDragging ? "touch-none" : undefined}
      {...attributes}
      {...listeners}
    />
  );
}

function stripColumnPrefix(id: string): string {
  return id.startsWith("column:") ? id.slice("column:".length) : id;
}

/** Midpoint between two neighbours, so only the moved row needs writing. */
function midpoint(before?: number, after?: number): number {
  if (before === undefined && after === undefined) return POSITION_STEP;
  if (before === undefined) return (after as number) - POSITION_STEP;
  if (after === undefined) return before + POSITION_STEP;
  return (before + after) / 2;
}
