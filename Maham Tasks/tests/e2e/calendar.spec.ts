import { expect, test } from "@playwright/test";

import { openDialog, signIn } from "./helpers";

/**
 * September 2026 is asked for by name rather than taken as "this month":
 * the seeded board is built around a fixed day, so the squares that hold
 * something are the same whenever these specs are run.
 */
const MONTH = "/calendar?month=2026-09";

test.describe("a day on the calendar", () => {
  test("opens even when nothing is due, and says so", async ({ page }) => {
    await signIn(page);
    await page.goto(MONTH);

    await page.getByRole("button", { name: /^Tuesday, 8 September, 0 due$/ }).click();
    const dialog = await openDialog(page);

    await expect(dialog).toContainText("8 September");
    await expect(dialog).toContainText("Nothing due that day");
  });

  test("lists what is due, and counts it", async ({ page }) => {
    await signIn(page);
    await page.goto(MONTH);

    // Three tasks land on the day the seeded board is built around.
    await page.getByRole("button", { name: /^Monday, 21 September, 3 due$/ }).click({ position: { x: 10, y: 10 } });
    const dialog = await openDialog(page);

    await expect(dialog).toContainText("21 September");
    await expect(dialog).toContainText("3 tasks");
    await expect(dialog.locator("ul > li")).toHaveCount(3);
    await expect(dialog).toContainText("Meet with Kuwait banks");
  });

  test("hands a task over to the task dialog, and leaves nothing behind", async ({ page }) => {
    await signIn(page);
    await page.goto(MONTH);

    await page.getByRole("button", { name: /^Monday, 21 September, 3 due$/ }).click({ position: { x: 10, y: 10 } });
    const day = await openDialog(page);
    await day.locator("ul > li button").first().click();

    // One dialog, not two stacked, and the page still answers afterwards.
    await expect(page.getByRole("dialog")).toHaveCount(1);
    await expect(page.getByRole("dialog").locator("#title")).toHaveValue(/\w/);

    await page.keyboard.press("Escape");
    await page.getByRole("button", { name: /^Wednesday, 9 September, 0 due$/ }).click();
    await expect(await openDialog(page)).toContainText("9 September");
  });
});
