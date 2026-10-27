import { describe, expect, it } from "vitest";

import { guideFor, type GuideFacts } from "@/lib/guide";

const fresh: GuideFacts = { telegramLinked: false, twoStep: false, holidays: 0, teamSize: 1, projects: 0 };
const nothing = { installed: false, ticked: new Set<string>() };

describe("the first-day guide", () => {
  it("gives an admin the setting-up, in order", () => {
    expect(guideFor("admin", fresh, nothing).map((item) => item.step)).toEqual([
      "home",
      "telegram",
      "twoStep",
      "team",
      "holidays",
      "project",
      "reports",
      "search",
    ]);
  });

  it("gives a member their own work, and nothing about running the office", () => {
    expect(guideFor("member", fresh, nothing).map((item) => item.step)).toEqual([
      "home",
      "telegram",
      "flow",
      "search",
    ]);
  });

  it("ticks what the app can see is done", () => {
    const done = guideFor(
      "admin",
      { telegramLinked: true, twoStep: true, holidays: 3, teamSize: 6, projects: 2 },
      { installed: true, ticked: new Set() },
    );
    expect(done.filter((item) => !item.done).map((item) => item.step)).toEqual(["reports", "search"]);
  });

  it("ticks the rest once they are done from the guide, but never a fact by hand", () => {
    const items = guideFor("manager", fresh, { installed: false, ticked: new Set(["search", "telegram"]) });
    expect(items.find((item) => item.step === "search")?.done).toBe(true);
    // Telegram is linked or it is not; a tick on this phone does not make it so.
    expect(items.find((item) => item.step === "telegram")?.done).toBe(false);
  });
});
