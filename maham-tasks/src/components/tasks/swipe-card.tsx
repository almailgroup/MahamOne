"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, Check, Eye, Play } from "lucide-react";
import { toast } from "sonner";

import { useHolidaySet } from "@/components/work-calendar/holidays-provider";
import { useOutbox } from "@/components/offline/outbox-provider";
import { moveTask, rescheduleTask } from "@/lib/data/task-actions";
import { formatDateTime, quickDateOptions } from "@/lib/dates";
import { statusMeta } from "@/lib/constants";
import { useI18n } from "@/lib/i18n/client";
import {
  cardOffset,
  isSideways,
  releasedAction,
  swipeActionsFor,
  SWIPE_COMMIT,
  SWIPE_START_PX,
  type SwipeAction,
} from "@/lib/swipe";
import type { TaskWithAssignees } from "@/lib/supabase/database.types";
import { cn } from "@/lib/utils";

type Gesture = {
  x: number;
  y: number;
  pointer: number;
  width: number;
  /** 1 when the page reads left to right, -1 in Arabic. */
  dir: 1 | -1;
  /** Undecided until it has moved far enough to tell. */
  sideways: boolean | null;
};

/**
 * A task card on a phone that can be swiped.
 *
 * Towards the end of the line moves the work on, towards the start puts it
 * off to the next working day (see lib/swipe). Each shows what it will do
 * underneath as the card slides, does it on release past about a third of
 * the card, and offers Undo. Everything a swipe does is also in the task
 * itself, so nobody has to know the gesture exists.
 */
export function SwipeCard({
  task,
  projectId,
  canComplete,
  canReschedule,
  className,
  children,
}: {
  task: TaskWithAssignees;
  projectId: string | null;
  canComplete: boolean;
  canReschedule: boolean;
  /** The card's own look: it is the part that slides. */
  className?: string;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const i18n = useI18n();
  const { t, tm, tag, timeZone } = i18n;
  const holidays = useHolidaySet();
  const { send } = useOutbox();

  const actions = swipeActionsFor(task, { canComplete, canReschedule });
  const swipeable = actions.forward !== null || actions.back !== null;

  const gesture = React.useRef<Gesture | null>(null);
  const offsetRef = React.useRef(0);
  const swiped = React.useRef(false);
  const [offset, setOffset] = React.useState(0);
  const [dragging, setDragging] = React.useState(false);
  const [dir, setDir] = React.useState<1 | -1>(1);
  const [width, setWidth] = React.useState(0);
  // Which side is showing. Held until the card has slid home, so what was
  // underneath does not vanish while the card is still on its way back.
  const [side, setSide] = React.useState<0 | 1 | -1>(0);

  const place = (next: number) => {
    offsetRef.current = next;
    setOffset(next);
    if (next !== 0) setSide(next > 0 ? 1 : -1);
  };

  function reset() {
    gesture.current = null;
    setDragging(false);
    place(0);
  }

  function onPointerDown(event: React.PointerEvent<HTMLDivElement>) {
    // A finger or a pen. A mouse selects text and drags the page.
    if (!swipeable || event.pointerType === "mouse" || !event.isPrimary) return;
    const element = event.currentTarget;
    gesture.current = {
      x: event.clientX,
      y: event.clientY,
      pointer: event.pointerId,
      width: element.offsetWidth,
      dir: getComputedStyle(element).direction === "rtl" ? -1 : 1,
      sideways: null,
    };
  }

  function onPointerMove(event: React.PointerEvent<HTMLDivElement>) {
    const current = gesture.current;
    if (!current || event.pointerId !== current.pointer) return;
    const dx = (event.clientX - current.x) * current.dir;
    const dy = event.clientY - current.y;

    if (current.sideways === null) {
      if (isSideways(dx, dy)) {
        current.sideways = true;
        try {
          event.currentTarget.setPointerCapture(event.pointerId);
        } catch {
          // A pointer the browser no longer tracks: follow it without capture.
        }
        setDir(current.dir);
        setWidth(current.width);
        setDragging(true);
      } else if (Math.abs(dy) > SWIPE_START_PX) {
        current.sideways = false;
      }
    }
    if (!current.sideways) return;

    const before = Math.abs(offsetRef.current) >= current.width * SWIPE_COMMIT;
    const next = cardOffset(dx, current.width, actions);
    const after = Math.abs(next) >= current.width * SWIPE_COMMIT;
    // A tick under the finger as it crosses the line, where phones allow it.
    if (before !== after) navigator.vibrate?.(8);
    place(next);
  }

  function onPointerUp(event: React.PointerEvent<HTMLDivElement>) {
    const current = gesture.current;
    if (!current || event.pointerId !== current.pointer) return;
    if (current.sideways) {
      // The tap that ends a swipe is not a tap on the card.
      swiped.current = true;
      const action = releasedAction(offsetRef.current, current.width, actions);
      if (action) void perform(action);
    }
    reset();
  }

  async function perform(action: SwipeAction) {
    if (action.kind === "status") {
      const from = task.status;
      const position = task.position;
      const outcome = await send({
        kind: "move",
        taskId: task.id,
        projectId: task.project_id ?? projectId,
        status: action.to,
        position: Date.now(),
        title: task.title,
      });
      // No signal: kept, and shown moved until it is sent.
      if (outcome === "kept") {
        toast(t("outbox.kept"));
        return;
      }
      if (!outcome.ok) {
        toast.error(tm(outcome.error));
        return;
      }
      router.refresh();
      // Closing a repeating task opens its next one, which an undo here
      // could not take back; that one is reopened from the task itself.
      const undoable = !(action.to === "done" && task.repeat_every);
      toast.success(t("swipe.moved", { title: task.title, status: t(statusMeta(action.to).label) }), {
        action: undoable
          ? {
              label: t("common.undo"),
              onClick: async () => {
                const back = await moveTask(task.id, task.project_id ?? projectId, from, position);
                if (!back.ok) toast.error(tm(back.error));
                router.refresh();
              },
            }
          : undefined,
      });
      return;
    }

    const was = task.due_at;
    const next = quickDateOptions(i18n, holidays)
      .find((option) => option.key === "nextWorkingDay")
      ?.value();
    if (!next) return;
    const outcome = await send({
      kind: "reschedule",
      taskId: task.id,
      projectId: task.project_id ?? projectId,
      dueAt: next,
      title: task.title,
    });
    if (outcome === "kept") {
      toast(t("outbox.kept"));
      return;
    }
    if (!outcome.ok) {
      toast.error(tm(outcome.error));
      return;
    }
    router.refresh();
    toast.success(t("resched.movedTo", { when: formatDateTime(next, tag, timeZone) }), {
      action: {
        label: t("common.undo"),
        onClick: async () => {
          const back = await rescheduleTask(task.id, task.project_id ?? projectId, was);
          if (!back.ok) toast.error(tm(back.error));
          router.refresh();
        },
      },
    });
  }

  const forward = actions.forward;
  const progress = width > 0 ? Math.min(1, Math.abs(offset) / (width * SWIPE_COMMIT)) : 0;
  const armed = progress >= 1;

  const forwardLabel =
    forward?.kind === "status"
      ? t(forward.to === "done" ? "swipe.done" : forward.to === "in_progress" ? "swipe.start" : "swipe.review")
      : "";
  const ForwardIcon =
    forward?.kind === "status" ? (forward.to === "done" ? Check : forward.to === "in_progress" ? Play : Eye) : Check;

  return (
    <li className="relative">
      {/* What the swipe will do, revealed as the card slides off it. */}
      {side !== 0 && (
        <div
          aria-hidden
          className={cn(
            "absolute inset-0 flex items-center rounded-[1.75rem] px-3 font-semibold transition-colors",
            side > 0
              ? cn("justify-start", armed ? "bg-primary text-primary-foreground" : "bg-primary/15 text-primary")
              : cn("justify-end", armed ? "bg-foreground/[0.16] text-foreground" : "bg-foreground/[0.07] text-muted-foreground"),
          )}
        >
          {/* Stacked and narrow, so it fits the gap a swipe opens before
              the card has gone far enough to act. */}
          <span
            className="flex w-24 flex-col items-center gap-1 text-center text-xs leading-tight transition-transform duration-150"
            style={{ transform: `scale(${0.85 + 0.15 * progress})`, opacity: 0.4 + 0.6 * progress }}
          >
            {side > 0 ? <ForwardIcon className="size-5" /> : <CalendarClock className="size-5" />}
            {side > 0 ? forwardLabel : t("quick.nextWorkingDay")}
          </span>
        </div>
      )}

      <div
        data-swipe-card
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={reset}
        onTransitionEnd={() => {
          if (offsetRef.current === 0) setSide(0);
        }}
        onClickCapture={(event) => {
          if (!swiped.current) return;
          swiped.current = false;
          event.preventDefault();
          event.stopPropagation();
        }}
        className={cn(
          // Vertical scrolling stays the browser's; sideways is the card's.
          swipeable && "touch-pan-y",
          !dragging && "transition-transform duration-300 ease-out motion-reduce:transition-none",
          className,
        )}
        style={offset !== 0 ? { transform: `translateX(${offset * dir}px)` } : undefined}
      >
        {children}
      </div>
    </li>
  );
}
