import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * Choosing a theme.
 *
 * The colours themselves are checked in tests/unit/themes.test.ts, contrast
 * included. What only a browser can say: picking one from the menu applies
 * it, the browser's own chrome follows, and it is still there tomorrow.
 */
test.describe("themes", () => {
  test("one is chosen from the menu, applied, and remembered", async ({ page }) => {
    await signIn(page);

    await page.getByRole("button", { name: "Theme" }).click();
    const menu = page.getByRole("menu");
    const html = page.locator("html");

    // Choosing does not close the menu: themes are tried on one after
    // another without opening it again each time.
    await page.getByRole("menuitem", { name: "Ocean" }).click();
    await expect(html).toHaveClass(/\bocean\b/);
    await expect(menu).toBeVisible();
    await page.getByRole("menuitem", { name: "Midnight" }).click();
    await expect(html).toHaveClass(/\bmidnight\b/);
    await expect(html).not.toHaveClass(/\bocean\b/);
    await expect(menu).toBeVisible();
    // It closes the usual way.
    await page.keyboard.press("Escape");
    await expect(menu).toBeHidden();

    // The page is wearing Midnight's ground, not Light's.
    const ground = () =>
      page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(await ground()).toBe("rgb(17, 26, 46)");

    // And the browser chrome follows, whatever the device's own setting is —
    // including after moving to another page, which re-renders the route's
    // metadata and puts fresh tags in with the default colours.
    const statusBar = page.locator('meta[name="theme-color"]').first();
    await expect(statusBar).toHaveAttribute("content", "#0b1120");
    // Exactly "Today": by substring this also matched a dashboard card whose
    // status update ends "— Admin, today", which on a phone comes first.
    await page
      .getByRole("link", { name: "Today", exact: true })
      .filter({ visible: true })
      .first()
      .click();
    await page.waitForURL(/\/today/, { timeout: 15_000 });
    await expect(statusBar).toHaveAttribute("content", "#0b1120");

    await page.reload();
    await expect(html).toHaveClass(/\bmidnight\b/);
    expect(await ground()).toBe("rgb(17, 26, 46)");

    // Back to the device's choice, so the shared browser state is left as found.
    await page.getByRole("button", { name: "Theme" }).click();
    await page.getByRole("menuitem", { name: "Match this device" }).click();
    await expect(html).not.toHaveClass(/\bmidnight\b/);
    await page.keyboard.press("Escape");
  });
});
