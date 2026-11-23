import { expect, type Page } from "@playwright/test";

/**
 * Signing in, for the specs that need a session.
 *
 * The mock backend hands back a token for whichever address is typed, so who
 * a spec is decides what it is allowed to see and do in the interface. The
 * password is never checked — these specs are about the app, and what a wrong
 * password does is covered against the real thing.
 *
 * State is shared: the mock keeps one workspace in memory for the whole run
 * and specs run in parallel, so nothing here asserts on a total. Anything a
 * spec creates carries a unique name and is found by that name.
 */
export const PEOPLE = {
  /** Sees everything, closes tasks, runs the team. */
  admin: { email: "admin@almailgroup.com", name: "Admin" },
  /** Plans work, and may close it. */
  manager: { email: "sara@almailgroup.com", name: "Sara Khan" },
  /** Does the work; cannot mark it done. */
  member: { email: "omar@almailgroup.com", name: "Omar Haddad" },
};

export async function signIn(page: Page, who = PEOPLE.admin, origin?: string) {
  // `origin` is for the specs that run against the second, small-page copy
  // of the app; everything else uses the config's baseURL.
  await page.goto(origin ? `${origin}/login` : "/login");
  await page.fill("#email", who.email);
  await page.fill("#password", "not-checked-by-the-mock");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL(/\/dashboard/, { timeout: 30_000 });
}

/** A name nothing else in the run will have. */
export const unique = (label: string) =>
  `${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/**
 * The control that opens a task, as *this* viewport shows it.
 *
 * Two things make the plain text match wrong. Every task view renders both
 * layouts and hides one with CSS — a table on a wide screen, cards on a
 * phone — so the text is found twice and the first copy is the invisible
 * half. And on a card the title sits in a `pointer-events-none` wrapper over
 * a stretched button, so the words themselves never take a tap.
 *
 * Both are facts about this app rather than quirks of one spec, which is why
 * every spec goes through here.
 */
export function taskNamed(page: Page, title: string) {
  const escaped = title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  // The table's control is the title itself; the card's is the stretched
  // button behind it, which announces "Open <title>".
  return page
    .getByRole("button", { name: new RegExp(`^(Open )?${escaped}$`) })
    .filter({ visible: true })
    .first();
}

/** The one dialog on screen, once it has finished arriving. */
export async function openDialog(page: Page) {
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible({ timeout: 10_000 });
  return dialog;
}
