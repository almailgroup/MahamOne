import { expect, test } from "@playwright/test";

const PAGES = ["/", "/login", "/forgot-password"];

for (const path of PAGES) {
  test.describe(path, () => {
    test("renders without a page error", async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));

      await page.goto(path);
      await expect(page.locator("body")).toBeVisible();
      expect(errors, `page errors on ${path}`).toEqual([]);
    });

    /**
     * The rule that keeps being broken by accident: a fixed-width element or a
     * row that will not wrap makes the whole page pan sideways on a phone.
     * Cheap to check, and it has caught real regressions here.
     */
    test("never scrolls sideways", async ({ page }) => {
      await page.goto(path);
      const overflows = await page.evaluate(
        () =>
          document.documentElement.scrollWidth >
          document.documentElement.clientWidth + 1,
      );
      expect(overflows, `${path} scrolls horizontally`).toBe(false);
    });

    test("every control is big enough to tap", async ({ page, isMobile }) => {
      test.skip(!isMobile, "Touch sizing only applies to a coarse pointer.");
      await page.goto(path);

      const tooSmall = await page.evaluate(() =>
        [...document.querySelectorAll("button, a, input, select, textarea")]
          .map((el) => ({ el, rect: el.getBoundingClientRect() }))
          .filter(({ rect }) => rect.width > 0 && rect.height > 0)
          .filter(({ rect }) => rect.height < 36 || rect.width < 32)
          .map(({ el, rect }) =>
            `${el.tagName} "${(el.getAttribute("aria-label") ?? el.textContent ?? "").trim().slice(0, 24)}" ${Math.round(rect.width)}x${Math.round(rect.height)}`,
          ),
      );
      expect(tooSmall).toEqual([]);
    });

    /**
     * iOS Safari zooms the page in when a field with text under 16px takes
     * focus, and leaves it zoomed afterwards — the single most common reason
     * a site "zooms in by itself" on a phone. The fields are deliberately
     * 14px on a mouse-driven screen, so this only applies to touch.
     */
    test("fields are large enough that a phone will not zoom in", async ({
      page,
      isMobile,
    }) => {
      test.skip(!isMobile, "Only a coarse pointer triggers the focus zoom.");
      await page.goto(path);

      const small = await page.evaluate(() =>
        [...document.querySelectorAll("input, select, textarea")]
          .filter((el) => el.getBoundingClientRect().height > 0)
          .map((el) => ({
            el,
            size: Number.parseFloat(getComputedStyle(el).fontSize),
          }))
          .filter(({ size }) => size < 16)
          .map(
            ({ el, size }) =>
              `${el.tagName}[${el.getAttribute("type") ?? "text"}] at ${size}px`,
          ),
      );
      expect(small).toEqual([]);
    });
  });
}

test("the browser is told to render the app at its own scale", async ({
  page,
}) => {
  await page.goto("/login");
  const content = await page
    .locator('meta[name="viewport"]')
    .getAttribute("content");
  expect(content).toContain("width=device-width");
  expect(content).toContain("initial-scale=1");
  expect(content).toContain("maximum-scale=1");
});

test("a signed-out visitor is sent to sign in, keeping their destination", async ({ page }) => {
  await page.goto("/dashboard");
  await page.waitForURL(/\/login/);
  expect(new URL(page.url()).searchParams.get("next")).toBe("/dashboard");
});

/**
 * Nobody signs themselves up. Accounts are added by an admin from the Team
 * page, and the database refuses any other kind — proven against Postgres in
 * supabase/tests/self-registration.sql. What a browser can check is that the
 * portal no longer offers it.
 */
test.describe("no self sign-up", () => {
  test("sign-in says who adds people, and offers no way to make an account", async ({
    page,
  }) => {
    await page.goto("/login");
    await expect(page.getByText("No account yet? Ask your admin to add you.")).toBeVisible();
    await expect(page.getByRole("link", { name: /create/i })).toHaveCount(0);
    await expect(page.locator('a[href="/register"]')).toHaveCount(0);
  });

  test("the front page offers only sign-in", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator('a[href="/register"]')).toHaveCount(0);
    await expect(page.getByRole("link", { name: /create an account/i })).toHaveCount(0);
  });

  test("an old link to the sign-up page lands on sign-in", async ({ page }) => {
    await page.goto("/register");
    await page.waitForURL(/\/login/);
    await expect(page.locator("#password")).toBeVisible();
  });
});
