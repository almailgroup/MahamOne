import { expect, test, type Page } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * One task waiting on another: linked from the task, shown in the lists while
 * the other is open, and gone from them once it is done.
 *
 * Who may link, the refusal of a circle, and the "ready to go" notification
 * are the database's, and are checked against a real Postgres in
 * supabase/tests/task-dependencies.sql.
 */
async function createTask(page: Page, title: string) {
  await page.goto("/general?new=1");
  const dialog = await openDialog(page);
  await dialog.locator("#title").fill(title);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });
}

test("a task waits on another until it is done", async ({ page }) => {
  const quote = unique("Get the quote approved");
  const deposit = unique("Pay the deposit");

  await signIn(page, PEOPLE.manager);
  await createTask(page, quote);
  await createTask(page, deposit);

  // Link them from the task that waits.
  await page.goto("/general");
  await taskNamed(page, deposit).click();
  const dialog = await openDialog(page);
  await dialog.getByLabel("Find a task this one waits on…").fill(quote.slice(0, 22));
  await dialog.getByRole("list", { name: "Matching tasks" }).getByRole("button", { name: new RegExp(quote) }).click();
  await expect(dialog.getByRole("button", { name: `Stop waiting on ${quote}` })).toBeAttached();
  await expect(dialog).toContainText("1 still open");
  await page.keyboard.press("Escape");

  // The list says so, beside the task.
  await page.goto("/tasks?filter=all");
  const waitingRow = page.locator("tr, li").filter({ has: taskNamed(page, deposit) }).filter({ visible: true }).first();
  await expect(waitingRow).toContainText("Waiting");

  // The other side of the link knows what it is holding up.
  await taskNamed(page, quote).click();
  const other = await openDialog(page);
  await expect(other.getByText("Waiting for this one")).toBeVisible();
  await expect(other).toContainText(deposit);

  // Finished, and the deposit is no longer waiting.
  await other.locator("#status").click();
  await page.getByRole("option", { name: "Done" }).click();
  await other.getByRole("button", { name: "Save changes" }).click();
  await expect(other).toBeHidden({ timeout: 15_000 });
  await page.goto("/tasks?filter=all");
  const freedRow = page.locator("tr, li").filter({ has: taskNamed(page, deposit) }).filter({ visible: true }).first();
  await expect(freedRow).toBeVisible();
  await expect(freedRow).not.toContainText("Waiting");
});

test("a member sees what a task waits on, but cannot change it", async ({ page }) => {
  const quote = unique("Sign the lease");
  const deposit = unique("Order the furniture");

  await signIn(page, PEOPLE.manager);
  await createTask(page, quote);
  await createTask(page, deposit);
  await page.goto("/general");
  await taskNamed(page, deposit).click();
  const dialog = await openDialog(page);
  await dialog.getByLabel("Find a task this one waits on…").fill(quote.slice(0, 14));
  await dialog.getByRole("list", { name: "Matching tasks" }).getByRole("button", { name: new RegExp(quote) }).click();
  await expect(dialog).toContainText("1 still open");
  await page.keyboard.press("Escape");

  await page.goto("/auth/signout");
  await signIn(page, PEOPLE.member);
  await page.goto("/tasks?filter=all");
  await taskNamed(page, deposit).click();
  const seen = await openDialog(page);
  await expect(seen.getByText("Waiting on")).toBeVisible();
  await expect(seen).toContainText(quote);
  await expect(seen.getByLabel("Find a task this one waits on…")).toHaveCount(0);
  await expect(seen.getByRole("button", { name: /^Stop waiting on/ })).toHaveCount(0);
});
