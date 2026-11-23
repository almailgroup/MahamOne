import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * Choosing a theme.
 *
 * The themes are Maham One's, measured by its own tests; the list is checked
 * in tests/unit/themes.test.ts. What only a browser can say: picking one from
 * the menu applies it, the browser's own chrome follows, and it is still
 * there tomorrow.
 */
test.describe("themes", () => {
  test("one is chosen from the menu, applied, and remembered", async ({ page }) => {
    await signIn(page);

    await page.getByRole("button", { name: "Theme" }).click();
    const menu = page.getByRole("menu");
    const html = page.locator("html");

    // Choosing does not close the menu: themes are tried on one after
    // another without opening it again each time.
    await page.getByRole("menuitem", { name: "Gulf blue" }).click();
    await expect(html).toHaveClass(/\bgulf\b/);
    await expect(menu).toBeVisible();
    await page.getByRole("menuitem", { name: "Midnight" }).click();
    await expect(html).toHaveClass(/\bmidnight\b/);
    await expect(html).not.toHaveClass(/\bgulf\b/);
    await expect(menu).toBeVisible();
    // It closes the usual way.
    await page.keyboard.press("Escape");
    await expect(menu).toBeHidden();

    // The page is wearing Midnight's dark ground, not Classic's white.
    const ground = () =>
      page.evaluate(() => {
        const probe = document.createElement("canvas").getContext("2d")!;
        probe.fillStyle = getComputedStyle(document.body).backgroundColor;
        probe.fillRect(0, 0, 1, 1);
        const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      });
    expect(await ground()).toBeLessThan(0.2);

    // And the browser chrome follows, whatever the device's own setting is —
    // including after moving to another page, which re-renders the route's
    // metadata and puts fresh tags in with the default colours.
    const statusBar = page.locator('meta[name="theme-color"]').first();
    await expect(statusBar).toHaveAttribute("content", "#0d1220");
    // Exactly "Today": by substring this also matched a dashboard card whose
    // status update ends "— Admin, today", which on a phone comes first.
    await page
      .getByRole("link", { name: "Today", exact: true })
      .filter({ visible: true })
      .first()
      .click();
    await page.waitForURL(/\/today/, { timeout: 15_000 });
    await expect(statusBar).toHaveAttribute("content", "#0d1220");

    await page.reload();
    await expect(html).toHaveClass(/\bmidnight\b/);
    expect(await ground()).toBeLessThan(0.2);

    // Back to the device's choice, so the shared browser state is left as found.
    await page.getByRole("button", { name: "Theme" }).click();
    await page.getByRole("menuitem", { name: "Match this device" }).click();
    await expect(html).not.toHaveClass(/\bmidnight\b/);
    await page.keyboard.press("Escape");
  });
});
