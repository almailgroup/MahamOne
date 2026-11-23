import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * Sorting a list on a phone.
 *
 * There are no column headings to tap there, so the order is chosen from a
 * small menu — which used to be a "Sort" button on a line of its own between
 * the search and the list. It lives in the search row now.
 */
test.describe("sorting on a phone", () => {
  test.skip(({ isMobile }) => !isMobile, "the table's headings sort on a desktop");

  test("is in the search row, and orders the list", async ({ page }) => {
    await signIn(page);
    await page.goto("/tasks?filter=all");

    const search = page.getByRole("textbox", { name: "Search tasks" });
    const sort = page.getByRole("button", { name: /^Sort/ }).filter({ visible: true });
    await expect(sort).toHaveCount(1);

    // Same row: the button sits within the search box's height, not below it.
    const [box, button] = [await search.boundingBox(), await sort.boundingBox()];
    const middle = button!.y + button!.height / 2;
    expect(middle).toBeGreaterThan(box!.y);
    expect(middle).toBeLessThan(box!.y + box!.height);

    const titles = page.locator("main ul li p.font-medium").filter({ visible: true });
    const firstTitle = () => titles.first().textContent();

    await sort.click();
    await page.getByRole("menuitem", { name: "Title" }).click();
    await expect(sort).toHaveAccessibleName("Sort: Title, ascending");
    const all = await titles.allTextContents();
    expect(all).toEqual([...all].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" })));

    // Again flips it.
    const ascendingFirst = await firstTitle();
    await sort.click();
    await page.getByRole("menuitem", { name: "Title" }).click();
    await expect(sort).toHaveAccessibleName("Sort: Title, descending");
    expect(await firstTitle()).not.toBe(ascendingFirst);
    expect(await titles.last().textContent()).toBe(ascendingFirst);

    // And the board's own order is one tap away.
    await sort.click();
    await page.getByRole("menuitem", { name: "Board order" }).click();
    await expect(sort).toHaveAccessibleName("Sort");
  });
});
