import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * Asking for the morning summary.
 *
 * What goes into it, and that it goes once a working morning, is checked
 * against a real Postgres in supabase/tests/office-reminders.sql. This checks
 * that somebody can ask for it, and that the page says when reminders go out.
 */
test("the morning summary can be switched on, and stays on", async ({ page }) => {
  // The admin's preferences are shared by every spec in the run: one project
  // at a time, and put back at the end.
  test.skip(test.info().project.name !== "desktop", "one copy of the preferences");

  await signIn(page);
  await page.goto("/profile");

  const summary = page.getByRole("checkbox", { name: "A summary of my day, each working morning" });
  await expect(summary).not.toBeChecked();
  await expect(page.getByText(/between 07:00 and 19:00 Kuwait time/)).toBeVisible();

  await summary.click();
  await page.getByRole("button", { name: "Save reminder settings" }).click();
  await expect(page.getByText("Reminder settings saved")).toBeVisible();

  await page.reload();
  await expect(summary).toBeChecked();

  await summary.click();
  await page.getByRole("button", { name: "Save reminder settings" }).click();
  await expect(page.getByText("Reminder settings saved")).toBeVisible();
});
