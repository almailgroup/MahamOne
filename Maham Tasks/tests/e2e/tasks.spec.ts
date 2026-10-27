import { expect, test } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

test.describe("the work itself", () => {
  test("a task can be created and is there afterwards", async ({ page }) => {
    const title = unique("Renew the trade licence");

    await signIn(page);
    // The same address the command palette's "New task" uses.
    await page.goto("/general?new=1");

    const dialog = await openDialog(page);
    await dialog.locator("#title").fill(title);
    await dialog.getByRole("button", { name: "Create task" }).click();
    await expect(dialog).toBeHidden({ timeout: 15_000 });

    await expect(page.getByText(title).filter({ visible: true }).first()).toBeVisible({ timeout: 15_000 });

    // Saved, not just drawn: a fresh page load has to find it too.
    await page.goto("/general");
    await expect(page.getByText(title).filter({ visible: true }).first()).toBeVisible({ timeout: 15_000 });
  });

  test("an admin can close a task", async ({ page }) => {
    const title = unique("Close me");

    await signIn(page);
    await page.goto("/general?new=1");
    const dialog = await openDialog(page);
    await dialog.locator("#title").fill(title);
    await dialog.getByRole("button", { name: "Create task" }).click();
    await expect(dialog).toBeHidden({ timeout: 15_000 });

    await taskNamed(page, title).click();
    const detail = await openDialog(page);
    await detail.locator("#status").click();
    await page.getByRole("option", { name: "Done" }).click();
    await detail.getByRole("button", { name: "Save changes" }).click();
    await expect(detail).toBeHidden({ timeout: 15_000 });

    await page.goto("/tasks?filter=all");
    await taskNamed(page, title).click();
    const again = await openDialog(page);
    await expect(again.locator("#status")).toContainText("Done");
  });
});

test.describe("work that comes back", () => {
  /**
   * Opening the next occurrence is a database trigger, and it is tested
   * where it lives — `supabase/tests/recurring-tasks.sql` against a real
   * Postgres. The mock runs no triggers, so what is checked here is the
   * other half: that a rule can be set, saved and read back.
   */
  test("a repeat rule is saved and comes back", async ({ page }) => {
    const title = unique("Reconcile the freight account");

    await signIn(page);
    await page.goto("/general?new=1");
    const dialog = await openDialog(page);
    await dialog.locator("#title").fill(title);
    // A repeat with no due date is refused, by the database and by the form.
    await dialog.locator("#dueAt").fill("2026-10-01T09:00");
    await dialog.locator("#repeatEvery").click();
    await page.getByRole("option", { name: "Weekly" }).click();
    await dialog.locator("#repeatInterval").fill("2");
    await dialog.getByRole("button", { name: "Create task" }).click();
    await expect(dialog).toBeHidden({ timeout: 15_000 });

    await page.goto("/general");
    await taskNamed(page, title).click();
    const again = await openDialog(page);
    await expect(again.locator("#repeatEvery")).toContainText("Weekly");
    await expect(again.locator("#repeatInterval")).toHaveValue("2");
  });

  test("a repeat needs a date to count from", async ({ page }) => {
    await signIn(page);
    await page.goto("/general?new=1");
    const dialog = await openDialog(page);
    await dialog.locator("#title").fill(unique("Undated repeat"));
    await dialog.locator("#repeatEvery").click();
    await page.getByRole("option", { name: "Monthly" }).click();
    await dialog.getByRole("button", { name: "Create task" }).click();

    // Said against the field, not thrown as a constraint violation.
    await expect(dialog.getByText("needs a due date")).toBeVisible({ timeout: 10_000 });
  });
});

test.describe("the review gate", () => {
  /**
   * The rule itself lives in row-level security and is verified against a
   * real Postgres — the mock backend enforces nothing. What is checked here
   * is that the interface states the rule rather than letting a member press
   * a button that the database will refuse.
   */
  test("a member is not offered Done", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/tasks?filter=all");

    await taskNamed(page, "Draft the September invoice").click();
    const dialog = await openDialog(page);
    // A member gets the progress view rather than the editor: they move the
    // task along, they do not re-plan it.
    await dialog.locator("#member-status").click();

    await expect(page.getByRole("option", { name: "In Review" })).toBeEnabled();
    await expect(page.getByRole("option", { name: "Done" })).toBeDisabled();
  });

  test("a manager is", async ({ page }) => {
    await signIn(page, PEOPLE.manager);
    await page.goto("/tasks?filter=all");

    await taskNamed(page, "Draft the September invoice").click();
    const dialog = await openDialog(page);
    await dialog.locator("#status").click();

    await expect(page.getByRole("option", { name: "Done" })).toBeEnabled();
  });
});
