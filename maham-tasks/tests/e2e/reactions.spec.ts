import { expect, test, type Page } from "@playwright/test";

import { openDialog, signIn, taskNamed, unique } from "./helpers";

/**
 * Reacting to a comment instead of replying "ok".
 *
 * Who may react is row-level security's business — supabase/tests/
 * comment-reactions.sql, against a real Postgres. Here: a reaction can be
 * added, it is still there after a reload, and a second tap takes it back.
 *
 * Each run makes its own task and comment. The desktop and phone runs sign in
 * as the same person against one shared workspace, so on a shared comment
 * each would be toggling the other's thumb.
 */

/** A fresh task with one comment on it, opened. */
async function taskWithComment(page: Page, title: string, words: string) {
  await page.goto("/general?new=1");
  const create = await openDialog(page);
  await create.locator("#title").fill(title);
  await create.getByRole("button", { name: "Create task" }).click();
  await expect(create).toBeHidden({ timeout: 15_000 });

  await taskNamed(page, title).click();
  const dialog = await openDialog(page);
  await dialog.getByRole("textbox", { name: "New comment" }).fill(words);
  await dialog.getByRole("button", { name: "Comment", exact: true }).click();
  await expect(dialog.getByRole("textbox", { name: "New comment" })).toHaveValue("", {
    timeout: 15_000,
  });

  // The thread hears about a new comment over realtime, which the mock does
  // not run, so open the task again to read it back.
  return reopen(page, title, words);
}

async function reopen(page: Page, title: string, words: string) {
  await page.goto("/general");
  await taskNamed(page, title).click();
  const dialog = await openDialog(page);
  await expect(dialog.getByText(words)).toBeVisible({ timeout: 15_000 });
  return dialog;
}

test.describe("reactions on a comment", () => {
  test("can be added, survive a reload, and be taken back", async ({ page }) => {
    const title = unique("Clear the Shuwaikh containers");
    const words = unique("Permits are in, trucks booked for Thursday");

    await signIn(page);
    let dialog = await taskWithComment(page, title, words);

    await dialog.getByText(words).hover();
    await dialog.getByRole("button", { name: "Add a reaction" }).click();
    // The picker opens in a layer of its own, outside the dialog.
    await page.getByRole("button", { name: "👍", exact: true }).click();

    const thumb = dialog.getByRole("button", { name: /^👍 1,/ });
    await expect(thumb).toBeVisible();
    await expect(thumb).toHaveAttribute("aria-pressed", "true");

    // Saved, not just drawn.
    dialog = await reopen(page, title, words);
    await expect(dialog.getByRole("button", { name: /^👍 1,/ })).toBeVisible({
      timeout: 15_000,
    });

    // The same tap takes it back, and that is saved too.
    await dialog.getByRole("button", { name: /^👍 1,/ }).click();
    await expect(dialog.getByRole("button", { name: /^👍/ })).toHaveCount(0);

    dialog = await reopen(page, title, words);
    await expect(dialog.getByRole("button", { name: /^👍/ })).toHaveCount(0);
  });
});
