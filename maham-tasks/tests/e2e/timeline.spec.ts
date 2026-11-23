import { expect, test, type Page } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * Milestones and the project timeline.
 *
 * The seeded Warehouse Move has one milestone, "Sulaibiya keys handed
 * over", with Camera installation and Staff parking list under it. Who may
 * set milestones, and which tasks may sit under them, is checked against a
 * real Postgres in supabase/tests/project-milestones.sql.
 *
 * The specs run on the real clock while the seed's dates are fixed, so
 * nothing here asserts whether a seeded milestone is late; the ones a spec
 * makes are dated from today.
 */

const WAREHOUSE = "/projects/11111111-1111-4111-8111-000000000002";
const BRAND = "/projects/11111111-1111-4111-8111-000000000003";
const SEEDED = "Sulaibiya keys handed over";

/** A day this many days from today, in Kuwait, as the date field takes it. */
function kuwaitDay(offset: number) {
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kuwait" }).format(new Date());
  const day = new Date(`${today}T12:00:00Z`);
  day.setUTCDate(day.getUTCDate() + offset);
  return day.toISOString().slice(0, 10);
}

async function openTimeline(page: Page, path: string) {
  await page.goto(path);
  await page.getByRole("tab", { name: "Timeline" }).click();
  return page.getByRole("list", { name: "Milestones" });
}

async function addMilestone(page: Page, title: string, offset: number) {
  await page.getByRole("button", { name: "Add a milestone" }).click();
  const form = page.getByRole("form", { name: "Add a milestone" });
  await form.getByLabel("Milestone name").fill(title);
  await form.getByLabel("Milestone date").fill(kuwaitDay(offset));
  await form.getByRole("button", { name: "Add" }).click();
  await expect(page.getByText(`Milestone added: ${title}`)).toBeVisible();
}

test("the timeline shows each milestone with the work under it", async ({ page }) => {
  await signIn(page, PEOPLE.member);
  const list = await openTimeline(page, WAREHOUSE);

  const card = list.getByRole("listitem").filter({ hasText: SEEDED });
  await expect(card).toBeVisible();
  await expect(card.getByRole("meter", { name: `${SEEDED}: 0 of 2 tasks done` })).toBeVisible();
  await expect(card.getByRole("button", { name: /Camera installation/ })).toBeVisible();
  await expect(card.getByRole("button", { name: /Staff parking list/ })).toBeVisible();

  // On the chart too: the milestone's marker, and a dot for each task.
  const chart = page.getByRole("region", { name: "Timeline" });
  await expect(chart.getByRole("button", { name: new RegExp(`^Milestone ${SEEDED}`) })).toBeVisible();
  await expect(chart.getByRole("button", { name: /^Camera installation, / })).toBeAttached();

  // A member reads the plan; setting it is for the people running it.
  await expect(page.getByRole("button", { name: "Add a milestone" })).toHaveCount(0);
  await expect(card.getByRole("button", { name: `Mark ${SEEDED} reached` })).toHaveCount(0);
});

test("a planner adds a milestone, gives it a task, and marks it reached", async ({ page }) => {
  const title = unique("Signage installed");
  const taskTitle = unique("Order the lightbox");

  await signIn(page, PEOPLE.manager);
  const list = await openTimeline(page, BRAND);
  await addMilestone(page, title, 10);

  const card = list.getByRole("listitem").filter({ hasText: title });
  await expect(card).toContainText("in 10 days");
  await expect(card).toContainText("No tasks under it yet");

  // A task started from the milestone goes under it.
  await card.getByRole("button", { name: `More for ${title}` }).click();
  await page.getByRole("menuitem", { name: "Add a task to it" }).click();
  const dialog = await openDialog(page);
  await expect(dialog.locator("#milestoneId")).toContainText(title);
  await dialog.locator("#title").fill(taskTitle);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });
  await expect(card.getByRole("button", { name: new RegExp(taskTitle) })).toBeVisible();
  await expect(card.getByRole("meter", { name: `${title}: 0 of 1 tasks done` })).toBeVisible();

  await card.getByRole("button", { name: `Mark ${title} reached` }).click();
  await expect(page.getByText(`${title}: reached`)).toBeVisible();
  await expect(card).toContainText("Reached");

  // Put away again; its task stays in the project, under none.
  await card.getByRole("button", { name: `More for ${title}` }).click();
  await page.getByRole("menuitem", { name: "Delete milestone" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete milestone" }).click();
  await expect(list.getByRole("listitem").filter({ hasText: title })).toHaveCount(0);
  await page.getByRole("tab", { name: "List" }).click();
  await expect(taskNamed(page, taskTitle)).toBeVisible();
});

test("a milestone past its date is marked late, in amber", async ({ page }) => {
  const title = unique("Permit renewed");

  await signIn(page, PEOPLE.manager);
  const list = await openTimeline(page, BRAND);
  await addMilestone(page, title, -3);

  const card = list.getByRole("listitem").filter({ hasText: title });
  const late = card.getByText("3 days late");
  await expect(late).toBeVisible();
  await expect(late).toHaveClass(/text-warning/);
  await expect(
    page.getByRole("region", { name: "Timeline" }).getByRole("button", { name: new RegExp(`^Milestone ${title}, late`) }),
  ).toBeVisible();

  await card.getByRole("button", { name: `More for ${title}` }).click();
  await page.getByRole("menuitem", { name: "Delete milestone" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete milestone" }).click();
  await expect(list.getByRole("listitem").filter({ hasText: title })).toHaveCount(0);
});

test("a planner moves a task under a milestone from the task", async ({ page }) => {
  const title = unique("Fit-out finished");

  await signIn(page, PEOPLE.manager);
  const list = await openTimeline(page, BRAND);
  await addMilestone(page, title, 20);

  // Website copy review is in Brand Refresh, under no milestone.
  await page
    .getByRole("region", { name: "Not under a milestone" })
    .getByRole("button", { name: /^Website copy review/ })
    .click();
  const dialog = await openDialog(page);
  await dialog.locator("#milestoneId").click();
  await page.getByRole("option", { name: new RegExp(`^${title}`) }).click();
  await dialog.getByRole("button", { name: "Save changes" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });

  const card = list.getByRole("listitem").filter({ hasText: title });
  await expect(card.getByRole("button", { name: /^Website copy review/ })).toBeVisible();

  // And back out, which also leaves the shared mock as it was.
  await card.getByRole("button", { name: /^Website copy review/ }).click();
  const again = await openDialog(page);
  await again.locator("#milestoneId").click();
  await page.getByRole("option", { name: "No milestone" }).click();
  await again.getByRole("button", { name: "Save changes" }).click();
  await expect(again).toBeHidden({ timeout: 15_000 });
  await expect(card.getByRole("button", { name: /^Website copy review/ })).toHaveCount(0);

  await card.getByRole("button", { name: `More for ${title}` }).click();
  await page.getByRole("menuitem", { name: "Delete milestone" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete milestone" }).click();
  await expect(list.getByRole("listitem").filter({ hasText: title })).toHaveCount(0);
});
