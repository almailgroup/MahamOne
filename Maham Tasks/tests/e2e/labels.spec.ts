import { expect, test } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * Labels: kept in Settings, put on a task from its form, shown on the task
 * wherever it is listed, and a list narrowed to one.
 *
 * The seeded workspace has "Bank" on "Meet with Kuwait banks" and "Ministry"
 * on nothing. Who may do what is checked against a real Postgres in
 * supabase/tests/labels.sql.
 */
test.describe("labels", () => {
  test("show on a task, and narrow a list to them", async ({ page }) => {
    await signIn(page);
    await page.goto("/tasks?filter=all");

    const bankTask = taskNamed(page, "Meet with Kuwait banks");
    await expect(bankTask).toBeVisible();
    // The pill sits beside the title, in whichever layout this viewport shows.
    const row = page
      .locator("tr, li")
      .filter({ has: bankTask })
      .filter({ visible: true })
      .first();
    await expect(row).toContainText("Bank");

    await page.getByRole("combobox", { name: "Label" }).filter({ visible: true }).click();
    await page.getByRole("option", { name: "Bank" }).click();
    await expect(page).toHaveURL(/label=99999999-9999-4999-8999-000000000001/);
    await expect(taskNamed(page, "Meet with Kuwait banks")).toBeVisible();
    await expect(taskNamed(page, "Sign the custody agreement")).toHaveCount(0);
  });

  test("a manager makes one in Settings and puts it on a new task", async ({ page }) => {
    const label = unique("Customs").slice(0, 30);
    const title = unique("Clear the shipment");

    await signIn(page, PEOPLE.manager);
    await page.goto("/settings");
    await page.getByLabel("New label").fill(label);
    await page.getByRole("radio", { name: "Teal" }).click();
    await page.getByRole("button", { name: "Add label" }).click();
    await expect(page.getByRole("list", { name: "Labels" })).toContainText(label);

    await page.goto("/general?new=1");
    const dialog = await openDialog(page);
    await dialog.locator("#title").fill(title);
    await dialog.getByRole("button", { name: "No labels" }).click();
    await page.getByRole("menuitem", { name: label }).click();
    await page.keyboard.press("Escape");
    await expect(dialog.getByRole("button", { name: `Remove label ${label}` })).toBeVisible();
    await dialog.getByRole("button", { name: "Create task" }).click();
    await expect(dialog).toBeHidden({ timeout: 15_000 });

    // Saved with the task: a fresh load shows it, and the form remembers it.
    await page.goto("/general");
    await taskNamed(page, title).click();
    const again = await openDialog(page);
    await expect(again.getByRole("button", { name: `Remove label ${label}` })).toBeVisible();
    await page.keyboard.press("Escape");

    // And removing the label takes it off.
    await page.goto("/settings");
    await page.getByRole("button", { name: `Delete ${label}` }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
    await expect(page.getByRole("list", { name: "Labels" })).not.toContainText(label);
  });

  test("a member sees a task's labels but is not offered to change them", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/tasks?filter=all");
    await taskNamed(page, "Meet with Kuwait banks").click();
    const dialog = await openDialog(page);
    await expect(dialog).toContainText("Bank");
    await expect(dialog.getByRole("button", { name: "No labels" })).toHaveCount(0);
    await expect(dialog.getByRole("button", { name: /^Remove label/ })).toHaveCount(0);
  });
});
