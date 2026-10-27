import { expect, test } from "@playwright/test";

import { openDialog, PEOPLE, signIn, unique } from "./helpers";

/**
 * Company holidays: an admin keeps the list in Settings, and the calendar
 * marks the days.
 *
 * The day is about two months out — inside the window the shell reads, and
 * far from the September board the other calendar specs count on. The mock is
 * shared by every spec, so the holiday is removed again at the end.
 */
function aWorkingDayAhead() {
  const day = new Date();
  day.setUTCDate(day.getUTCDate() + 60);
  // Sunday to Thursday: a holiday on a weekend would mark nothing new.
  while (day.getUTCDay() === 5 || day.getUTCDay() === 6) day.setUTCDate(day.getUTCDate() + 1);
  return day;
}

test.describe("company holidays", () => {
  test("an admin adds one, the calendar marks it, and it can be removed", async ({ page }) => {
    const name = unique("Founders Day");
    const day = aWorkingDayAhead();
    const iso = day.toISOString().slice(0, 10);

    await signIn(page);
    await page.goto("/settings");

    await page.getByLabel("Name").fill(name);
    await page.getByLabel("First day").fill(iso);
    await page.getByRole("button", { name: "Add holiday" }).click();

    const list = page.getByRole("list", { name: "Company holidays" });
    await expect(list).toContainText(name);
    await expect(list.getByRole("listitem").filter({ hasText: name })).toContainText("1 day");

    await page.goto(`/calendar?month=${iso.slice(0, 7)}`);
    const cell = page.getByRole("button", { name: new RegExp(`Holiday: ${name}$`) });
    await expect(cell).toHaveCount(1);
    await cell.click({ position: { x: 10, y: 10 } });
    const dialog = await openDialog(page);
    await expect(dialog).toContainText(`Holiday: ${name}`);
    await page.keyboard.press("Escape");

    await page.goto("/settings");
    await page.getByRole("button", { name: `Remove ${name}` }).click();
    await expect(page.getByRole("button", { name: `Remove ${name}` })).toHaveCount(0);
  });

  test("a manager reads the list but cannot change it", async ({ page }) => {
    await signIn(page, PEOPLE.manager);
    await page.goto("/settings");

    await expect(page.getByRole("heading", { name: "Company holidays" })).toBeVisible();
    await expect(page.getByText("Only an admin can change the holidays.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Add holiday" })).toHaveCount(0);
  });

  test("a member is sent back to the dashboard", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/settings");
    await page.waitForURL(/\/dashboard/);
  });
});
