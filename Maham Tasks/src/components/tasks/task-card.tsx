"use client";

import * as React from "react";
import { MessageSquare, Timer } from "lucide-react";

import {
  AssigneeStack,
  DueDate,
  PriorityIndicator,
  ChecklistProgressBadge,
  WaitingBadge,
  RepeatBadge,
} from "@/components/tasks/task-meta";
import { compactAge, formatElapsed } from "@/lib/dates";
import { useNow } from "@/lib/use-now";
import { cn } from "@/lib/utils";
import { LabelPills } from "@/components/labels/label-pills";
import { useI18n } from "@/lib/i18n/client";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";

/**
 * Kanban card. Compact by design — title, priority ramp, due date, assignees —
 * with everything else living in the task modal.
 */
export const TaskCard = React.forwardRef<
  HTMLDivElement,
  {
    task: TaskWithAssignees;
    onOpen?: () => void;
    /** Status control, so a card can be moved without dragging it. */
    move?: React.ReactNode;
    dragging?: boolean;
    className?: string;
  } & React.HTMLAttributes<HTMLDivElement>
>(function TaskCard({ task, onOpen, move, dragging, className, ...props }, ref) {
  /**
   * Whether the pointer wandered between press and release.
   *
   * The sensors already stop a click becoming a drag — four pixels for a
   * mouse, a long press for a thumb. This is the other direction: a browser
   * fires `click` whenever press and release land on the same element, however
   * far the pointer travelled in between, so dragging a card and putting it
   * back opened it.
   *
   * It has to watch the whole journey rather than compare the two ends, which
   * was the first attempt and reported no movement at all for exactly the
   * gesture it was meant to catch: picking a card up, moving it, and dropping
   * it where it started.
   */
  const pressedAt = React.useRef<{ x: number; y: number } | null>(null);
  const wandered = React.useRef(false);

  /**
   * Open, unless that press was really a drag.
   *
   * Shared by the card and the title inside it. The title needs it as much as
   * the card does — picking a card up by its title, moving it and dropping it
   * back has always opened the task, because the browser sees one press and
   * one release on the same button and calls that a click.
   */
  const openUnlessDragged = () => {
    const dragged = wandered.current;
    pressedAt.current = null;
    wandered.current = false;
    if (!dragged) onOpen?.();
  };

  const openFromCard = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!onOpen) return;

    // Anything with its own behaviour keeps it: the status control, and the
    // title, which opens through its own handler rather than this one.
    if ((event.target as HTMLElement).closest("button, a, input, [role='menu']")) {
      return;
    }

    openUnlessDragged();
  };

  return (
    <div
      ref={ref}
      className={cn(
        "group lift rounded-2xl bg-card p-3.5 shadow-[var(--shadow-sm)] sm:p-4",
        "hover:border-foreground/30",
        // The whole card opens the task. Only the title did, which is a small
        // target on something that looks pressable end to end — and on a phone
        // it was a game of hitting one line of text.
        onOpen && "cursor-pointer",
        dragging && "opacity-40",
        className,
      )}
      {...props}
      onPointerDown={(event) => {
        pressedAt.current = { x: event.clientX, y: event.clientY };
        wandered.current = false;
        props.onPointerDown?.(event);
      }}
      onPointerMove={(event) => {
        const from = pressedAt.current;
        if (from && Math.hypot(event.clientX - from.x, event.clientY - from.y) > 5) {
          wandered.current = true;
        }
        props.onPointerMove?.(event);
      }}
      onClick={(event) => {
        openFromCard(event);
        props.onClick?.(event);
      }}
    >
      <button
        type="button"
        onClick={openUnlessDragged}
        // Still a real button, so the card can be reached and opened from the
        // keyboard. The handler above is an addition for pointers, not a
        // replacement for this.
        className="w-full text-start focus-visible:outline-none pointer-coarse:-my-2 pointer-coarse:py-2"
      >
        <p className="text-[0.9375rem] font-medium leading-snug">{task.title}</p>
      </button>
      {/* Outside the button, so its name stays the task's title. */}
      <LabelPills ids={task.labelIds} className="mt-1.5" />

      {/* One row, wrapping only when it has to. The status control used to be
          given a line of its own below this one — forty-odd pixels a card, on
          every board and every phone — and it wraps here to exactly the same
          place when the card is too narrow to hold it. */}
      <div className="mt-2.5 flex flex-wrap items-center gap-x-2 gap-y-1.5">
        <PriorityIndicator priority={task.priority} />
        <DueDate dueAt={task.due_at} status={task.status} />
                  <RepeatBadge every={task.repeat_every} interval={task.repeat_interval} />
                  <ChecklistProgressBadge progress={task.checklist} />
                  <WaitingBadge count={task.waitingOn} status={task.status} />
        <ElapsedSinceCreated createdAt={task.created_at} />
        <span className="ms-auto flex items-center gap-2">
          <AssigneeStack assignees={task.assignees} max={2} />
          {move}
        </span>
      </div>
    </div>
  );
});

/**
 * How long the task has been open.
 *
 * Shown compactly — "3d" — and folded onto the meta row rather than given a
 * divider and a line of its own: it is context, not a headline. The exact
 * hh:mm:ss and the creation timestamp are in the tooltip.
 *
 * Renders a placeholder before hydration rather than nothing, so the card
 * does not change width the moment the clock starts.
 */
function ElapsedSinceCreated({ createdAt }: { createdAt: string }) {
  const now = useNow();
  const i18n = useI18n();
  const { t, tag } = i18n;

  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 text-xs tabular-nums text-muted-foreground"
      // Formatted with the viewer's locale, so it waits for hydration too.
      title={
        now === null
          ? undefined
          : t("card.openFor", {
              elapsed: formatElapsed(createdAt, now),
              created: new Date(createdAt).toLocaleString(tag),
            })
      }
    >
      <Timer className="size-3 shrink-0" />
      {now === null ? "—" : compactAge(createdAt, now, i18n)}
      <span className="sr-only">{t("card.sinceCreated")}</span>
    </span>
  );
}

/** Screen-reader hint describing how to move a card with the keyboard. */
export function DragInstructions() {
  const { t } = useI18n();
  return (
    <p className="sr-only" id="kanban-drag-instructions">
      {t("kanban.dragInstructions")}
    </p>
  );
}

export { MessageSquare };
