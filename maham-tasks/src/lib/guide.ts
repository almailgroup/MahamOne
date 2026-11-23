import type { UserRole } from "@/lib/supabase/database.types";

/**
 * The first-day guide: the handful of things worth doing in the first week,
 * in the order worth doing them, for each kind of account.
 *
 * Where the app can tell a step is done it ticks itself — Telegram linked,
 * two-step on, holidays in — so the list never asks for something already
 * done. The rest are ticked by doing them from the guide.
 */

export const GUIDE_STEPS = [
  "home",
  "telegram",
  "twoStep",
  "team",
  "holidays",
  "project",
  "flow",
  "reports",
  "search",
] as const;

export type GuideStep = (typeof GUIDE_STEPS)[number];

/** What the server knows about this account's setup. */
export type GuideFacts = {
  telegramLinked: boolean;
  /** Only asked for an admin. */
  twoStep: boolean;
  holidays: number;
  teamSize: number;
  projects: number;
};

const FOR: Record<GuideStep, readonly UserRole[]> = {
  home: ["admin", "manager", "member"],
  telegram: ["admin", "manager", "member"],
  twoStep: ["admin"],
  team: ["admin"],
  holidays: ["admin"],
  project: ["admin", "manager"],
  flow: ["member"],
  reports: ["admin", "manager"],
  search: ["admin", "manager", "member"],
};

export type GuideItem = { step: GuideStep; done: boolean };

export function guideFor(
  role: UserRole,
  facts: GuideFacts,
  { installed, ticked }: { installed: boolean; ticked: ReadonlySet<string> },
): GuideItem[] {
  const known: Partial<Record<GuideStep, boolean>> = {
    home: installed,
    telegram: facts.telegramLinked,
    twoStep: facts.twoStep,
    team: facts.teamSize > 1,
    holidays: facts.holidays > 0,
    project: facts.projects > 0,
  };
  return GUIDE_STEPS.filter((step) => FOR[step].includes(role)).map((step) => ({
    step,
    done: known[step] ?? ticked.has(step),
  }));
}
