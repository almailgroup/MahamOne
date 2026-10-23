import type { TaskStatus } from "@/lib/supabase/database.types";

/**
 * What a swipe on a phone's task card does, worked out without the gesture.
 *
 * Towards the end of the line (right in English, left in Arabic) moves the
 * work on: a planner closes it; a member, who cannot close work, starts it
 * or sends it for review. Towards the start puts it off to the next working
 * day, which only planners may do, since only they set dates.
 */

export type SwipeAction =
  | { kind: "status"; to: TaskStatus }
  | { kind: "nextWorkingDay" };

export type SwipeActions = { forward: SwipeAction | null; back: SwipeAction | null };

export function swipeActionsFor(
  task: { status: TaskStatus },
  { canComplete, canReschedule }: { canComplete: boolean; canReschedule: boolean },
): SwipeActions {
  let forward: SwipeAction | null = null;
  if (task.status !== "done") {
    if (canComplete) forward = { kind: "status", to: "done" };
    else if (task.status === "todo") forward = { kind: "status", to: "in_progress" };
    else if (task.status === "in_progress") forward = { kind: "status", to: "in_review" };
  }
  const back: SwipeAction | null =
    canReschedule && task.status !== "done" ? { kind: "nextWorkingDay" } : null;
  return { forward, back };
}

/** Sideways and far enough to be a swipe, not a wobble on the way to a scroll. */
export const SWIPE_START_PX = 12;

/** How far, as a share of the card, a swipe must go to count. */
export const SWIPE_COMMIT = 0.38;

/** Past the threshold the card keeps following, but more slowly. */
const RESISTANCE = 0.35;

/**
 * Whether a gesture that has moved this far is a sideways swipe. Vertical
 * movement wins ties: the list scrolls far more often than it is swiped.
 */
export function isSideways(dx: number, dy: number): boolean {
  return Math.abs(dx) >= SWIPE_START_PX && Math.abs(dx) > Math.abs(dy) * 1.5;
}

/**
 * Where the card sits for a finger `dx` along (in reading direction: positive
 * is towards the end), given which directions have an action. A direction
 * with nothing to do does not move at all.
 */
export function cardOffset(dx: number, width: number, actions: SwipeActions): number {
  if (dx > 0 && !actions.forward) return 0;
  if (dx < 0 && !actions.back) return 0;
  const limit = width * SWIPE_COMMIT;
  const distance = Math.abs(dx);
  const eased = distance <= limit ? distance : limit + (distance - limit) * RESISTANCE;
  return Math.sign(dx) * Math.min(eased, width * 0.8);
}

/** Which action, if any, a swipe released at `offset` triggers. */
export function releasedAction(offset: number, width: number, actions: SwipeActions): SwipeAction | null {
  if (width <= 0 || Math.abs(offset) < width * SWIPE_COMMIT) return null;
  return offset > 0 ? actions.forward : actions.back;
}
