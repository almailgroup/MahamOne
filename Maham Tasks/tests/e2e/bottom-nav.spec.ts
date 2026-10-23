import { expect, test, type Locator } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * The phone's navigation bar.
 *
 * The page you are on is marked twice: for a screen reader, as the current
 * page, and for the eye, by its icon rising out of the row in a filled pill.
 * The rise is the thing people asked for, so it is measured, not assumed.
 */
test.describe("bottom navigation", () => {
  test.skip(({ isMobile }) => !isMobile, "the rail replaces it on a desktop");

  /**
   * How far the icon and label sit above the middle of their button, in
   * pixels. Measured from where they are drawn rather than from a style:
   * Tailwind moves things with `translate`, not `transform`, and a test that
   * read the wrong one passed with the lift taken out.
   */
  const rise = (link: Locator) =>
    link.evaluate((el) => {
      const box = el.getBoundingClientRect();
      const glyph = el.firstElementChild!.getBoundingClientRect();
      return Math.round(box.top + box.height / 2 - (glyph.top + glyph.height / 2));
    });

  test("lifts the page you are on, and only that one", async ({ page }) => {
    await signIn(page);
    const bar = page.getByRole("navigation", { name: "Tasks" }).filter({ visible: true });
    const tasks = bar.getByRole("link", { name: "Tasks" });
    const home = bar.getByRole("link", { name: "Home" });

    await expect(home).toHaveAttribute("aria-current", "page");
    await expect.poll(() => rise(home)).toBeGreaterThan(2);
    await expect.poll(() => rise(tasks)).toBeCloseTo(0);

    await tasks.click();
    await page.waitForURL(/\/tasks/);
    await expect(tasks).toHaveAttribute("aria-current", "page");
    await expect(home).not.toHaveAttribute("aria-current", "page");
    // The spring settles; the old page comes back down.
    await expect.poll(() => rise(tasks)).toBeGreaterThan(2);
    await expect.poll(() => rise(home)).toBeCloseTo(0);
  });

  test("leaves the bottom of every page clear of it", async ({ page }) => {
    await signIn(page);
    await page.goto("/tasks?filter=all");
    const cards = page.locator("main li").filter({ visible: true });
    await expect(cards.first()).toBeVisible();
    // Scrolled to the end, the last card ends above the bar, not beneath it.
    const bar = page.getByRole("navigation", { name: "Tasks" }).filter({ visible: true });
    await expect
      .poll(async () => {
        await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
        const [card, nav] = [await cards.last().boundingBox(), await bar.boundingBox()];
        return nav!.y - (card!.y + card!.height);
      })
      .toBeGreaterThanOrEqual(0);
  });
});
