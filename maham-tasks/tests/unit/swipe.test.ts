import { describe, expect, it } from "vitest";

import { cardOffset, isSideways, releasedAction, swipeActionsFor, SWIPE_COMMIT } from "@/lib/swipe";

const planner = { canComplete: true, canReschedule: true };
const member = { canComplete: false, canReschedule: false };

describe("what a swipe does", () => {
  it("closes work for a planner, and puts it off to the next working day", () => {
    expect(swipeActionsFor({ status: "in_progress" }, planner)).toEqual({
      forward: { kind: "status", to: "done" },
      back: { kind: "nextWorkingDay" },
    });
  });

  it("moves a member's work on a step, never to done, and never re-dates it", () => {
    expect(swipeActionsFor({ status: "todo" }, member)).toEqual({
      forward: { kind: "status", to: "in_progress" },
      back: null,
    });
    expect(swipeActionsFor({ status: "in_progress" }, member).forward).toEqual({
      kind: "status",
      to: "in_review",
    });
    expect(swipeActionsFor({ status: "in_review" }, member).forward).toBeNull();
  });

  it("does nothing to finished work", () => {
    expect(swipeActionsFor({ status: "done" }, planner)).toEqual({ forward: null, back: null });
  });
});

describe("the gesture", () => {
  const both = swipeActionsFor({ status: "todo" }, planner);
  const onlyForward = swipeActionsFor({ status: "todo" }, member);

  it("lets a scroll be a scroll", () => {
    expect(isSideways(8, 0)).toBe(false);
    expect(isSideways(20, 18)).toBe(false);
    expect(isSideways(30, 6)).toBe(true);
    expect(isSideways(-30, 6)).toBe(true);
  });

  it("follows the finger to the threshold, then slows", () => {
    expect(cardOffset(100, 400, both)).toBe(100);
    const limit = 400 * SWIPE_COMMIT;
    expect(cardOffset(limit + 100, 400, both)).toBeCloseTo(limit + 35);
    expect(cardOffset(-100, 400, both)).toBe(-100);
  });

  it("does not move towards a side with nothing to do", () => {
    expect(cardOffset(-100, 400, onlyForward)).toBe(0);
  });

  it("acts only past the threshold, in the direction released", () => {
    expect(releasedAction(100, 400, both)).toBeNull();
    expect(releasedAction(160, 400, both)).toEqual({ kind: "status", to: "done" });
    expect(releasedAction(-160, 400, both)).toEqual({ kind: "nextWorkingDay" });
  });
});
