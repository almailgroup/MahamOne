import { expect, test } from "@playwright/test";

import { openDialog, signIn, taskNamed, unique } from "./helpers";

/**
 * The daily review's fifth question.
 *
 * Today asks four things about work that is not done, and one about work
 * that is: what got finished. When the page was narrowed to a bounded read
 * of open tasks, that fifth answer was left deriving from the same list —
 * which excludes every row it is about — so the line never appeared again.
 * Nothing caught it, because "no completed work today" is what a quiet day
 * looks like too.
 *
 * Asserted as presence, never as a count: the mock keeps one workspace for
 * the whole run and other specs close tasks in it.
 */
test.describe("the daily review", () => {
  test("says what was finished today", async ({ page }) => {
    const title = unique("Finish me today");

    await signIn(page);

    // Nothing is seeded as finished *today*, so the spec closes its own.
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

    await page.goto("/today");
    await expect(page.getByText(/completed today/i)).toBeVisible({
      timeout: 15_000,
    });
  });
});
