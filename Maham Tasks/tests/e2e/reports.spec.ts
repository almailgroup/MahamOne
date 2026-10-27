import { expect, test } from "@playwright/test";

import { PEOPLE, signIn } from "./helpers";

/**
 * The Reports page: the headline numbers, the period week by week, open work
 * by person, and the projects — each chart with a table of the same numbers.
 *
 * What is counted, and over whose rows, is the database's: checked against a
 * real Postgres in supabase/tests/work-report.sql.
 */
test("a manager reads the reports, as charts and as tables", async ({ page }) => {
  await signIn(page, PEOPLE.manager);
  await page.goto("/reports?period=12w");

  await expect(page.getByRole("heading", { name: "Reports", level: 1 })).toBeVisible();
  await expect(page.getByRole("link", { name: "Last 12 weeks" })).toHaveAttribute("aria-current", "page");
  for (const tile of ["Finished", "Added", "Finished on time", "Overdue now"]) {
    await expect(page.getByText(tile, { exact: true }).first()).toBeVisible();
  }

  // Week by week: a column chart, with every week reachable by keyboard.
  const weeks = page.getByRole("region", { name: "Week by week" });
  await expect(weeks.locator("svg[data-chart]")).toBeVisible();
  await expect(weeks.getByRole("img", { name: /^Week of / }).first()).toBeAttached();
  await weeks.getByRole("button", { name: "Table" }).click();
  await expect(weeks.getByRole("table")).toBeVisible();
  await expect(weeks.getByRole("columnheader", { name: "Finished" })).toBeVisible();

  // Open work by person, longest first, with overdue counted.
  const people = page.getByRole("region", { name: "Open work by person" });
  await expect(people.getByRole("listitem").first()).toHaveAccessibleName(/open, \d+ overdue$/);

  // And each project's progress.
  const projects = page.getByRole("region", { name: "Projects" });
  await expect(projects.getByRole("meter", { name: "Kuwait Bank Portal" })).toBeVisible();
  await expect(projects).not.toContainText("2025 Audit");
});

test("this year is shown month by month", async ({ page }) => {
  await signIn(page);
  await page.goto("/reports");
  await page.getByRole("link", { name: "This year" }).click();
  await page.waitForURL(/period=year/);
  await expect(page.getByRole("region", { name: "Month by month" })).toBeVisible();
});

test("a member is sent back to the dashboard", async ({ page }) => {
  await signIn(page, PEOPLE.member);
  await page.goto("/reports");
  await page.waitForURL(/\/dashboard/);
});
