import { expect, test } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * Task templates: start a task from one, steps and all; save a task as one.
 *
 * The seeded workspace has "Month-end payroll": title "Run payroll", high
 * priority, the Bank label, three steps, due three working days out. Who may
 * keep templates is checked against a real Postgres in
 * supabase/tests/task-templates.sql.
 */
test("a new task starts from a template, steps and all", async ({ page }) => {
  const title = unique("Run payroll");

  await signIn(page, PEOPLE.manager);
  await page.goto("/general?new=1");
  const dialog = await openDialog(page);

  await dialog.getByLabel("Start from a template").click();
  await page.getByRole("option", { name: "Month-end payroll" }).click();

  await expect(dialog.locator("#title")).toHaveValue("Run payroll");
  await expect(dialog.locator("#description")).toHaveValue(/Salaries for the month/);
  await expect(dialog.locator("#priority")).toContainText("High");
  await expect(dialog.locator("#dueAt")).not.toHaveValue("");
  await expect(dialog).toContainText("Brings 3 steps with it.");
  await expect(dialog.getByRole("button", { name: "Remove label Bank" })).toBeVisible();

  await dialog.locator("#title").fill(title);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });

  await page.goto("/tasks?filter=all");
  await taskNamed(page, title).click();
  const made = await openDialog(page);
  await expect(made).toContainText("Collect timesheets");
  await expect(made).toContainText("Check overtime");
  await expect(made).toContainText("Send to the bank");
});

test("a task is saved as a template, and offered in Settings", async ({ page }) => {
  const title = unique("Renew the trade licence");

  await signIn(page, PEOPLE.manager);
  await page.goto("/general?new=1");
  const dialog = await openDialog(page);
  await dialog.locator("#title").fill(title);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });

  await page.goto("/tasks?filter=all");
  await taskNamed(page, title).click();
  const opened = await openDialog(page);
  await opened.getByRole("button", { name: "Save as a template" }).click();
  await expect(page.getByText(`Saved as the template “${title}”.`)).toBeVisible();
  await page.keyboard.press("Escape");

  await page.goto("/settings");
  await expect(page.getByRole("list", { name: "Task templates" })).toContainText(title);

  // And put away again, which also leaves the shared mock as it was.
  await page.getByRole("button", { name: `Delete ${title}` }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await expect(page.getByRole("list", { name: "Task templates" })).not.toContainText(title);
});

test("a member is not offered to save a template", async ({ page }) => {
  await signIn(page, PEOPLE.member);
  await page.goto("/tasks?filter=all");
  await taskNamed(page, "Meet with Kuwait banks").click();
  const dialog = await openDialog(page);
  await expect(dialog.getByRole("button", { name: "Save as a template" })).toHaveCount(0);
});
