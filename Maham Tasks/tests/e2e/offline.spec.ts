import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * The app on a phone with no signal.
 *
 * Installed to a home screen there is no address bar to explain a failure,
 * so without any of this a dropped connection looks like the app being
 * broken. These pin the three things that stop that: the worker registers,
 * the offline page is cached and reachable, and a navigation with no network
 * lands on it rather than on the browser's error page.
 */
test.describe("with no connection", () => {
  test("the service worker takes over", async ({ page }) => {
    await signIn(page);

    // It registers after `load`, deliberately, so this waits for it rather
    // than assuming it is there by the time the dashboard paints.
    await expect
      .poll(
        () =>
          page.evaluate(async () => {
            const registration = await navigator.serviceWorker.getRegistration();
            return Boolean(registration?.active);
          }),
        { timeout: 20_000 },
      )
      .toBe(true);
  });

  test("the offline page is cached, and reachable without a session", async ({
    page,
    context,
  }) => {
    await signIn(page);

    /** What the worker's cache holds, by path. */
    const cached = () =>
      page.evaluate(async () => {
        const name = (await caches.keys()).find((key) => key.startsWith("almail-"));
        if (!name) return [];
        const cache = await caches.open(name);
        return (await cache.keys()).map((request) => new URL(request.url).pathname);
      });

    await expect.poll(cached, { timeout: 20_000 }).toContain("/offline");

    // A page that only works with a connection would be a poor offline page.
    const response = await context.request.get("/offline");
    expect(response.status()).toBe(200);

    // And everything it needs to draw and come to life — its scripts, styles
    // and fonts — is in the cache with it. Without them the page arrived as
    // bare HTML: no offline bar, no language, nothing that answered a tap.
    // Playwright's offline switch does not reach the worker's own requests,
    // so a test that only went offline could not see this; the cache can.
    const html = await response.text();
    const assets = [...new Set(html.match(/\/_next\/static\/[^"'\s\\]+/g) ?? [])];
    expect(assets.length).toBeGreaterThan(0);
    const held = await cached();
    expect(assets.filter((asset) => !held.includes(decodeURI(asset)))).toEqual([]);
  });

  test("a navigation lands on it rather than on a browser error", async ({
    page,
    context,
  }) => {
    await signIn(page);
    await expect
      .poll(
        () =>
          page.evaluate(async () =>
            Boolean((await navigator.serviceWorker.getRegistration())?.active),
          ),
        { timeout: 20_000 },
      )
      .toBe(true);

    await context.setOffline(true);
    await page.goto("/today").catch(() => {
      // The navigation itself may reject; what matters is what is on screen.
    });

    await expect(page.getByRole("heading", { name: "No connection" })).toBeVisible({
      timeout: 15_000,
    });
    // And the bar that says why, which is the only thing telling somebody
    // their next edit will not be saved.
    await expect(page.getByText(/Offline —/)).toBeVisible();

    await context.setOffline(false);
  });

  test("the worker itself is never behind the sign-in redirect", async ({ context }) => {
    // A 307 to /login cannot be registered as a service worker, and the
    // browser would not try again for a day.
    const response = await context.request.get("/sw.js");
    expect(response.status()).toBe(200);
    expect(await response.text()).toContain("addEventListener");
  });
});
