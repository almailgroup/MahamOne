import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * A second copy of the app, started by the config with a page size of five.
 * Every other spec runs against the ordinary one, which still carries the
 * whole seeded workspace.
 */
const SMALL = process.env.SMALL_URL ?? "http://127.0.0.1:3211";

/**
 * What a page does when there is more work than it can carry.
 *
 * Every task view used to ask for every task with no limit. PostgREST caps a
 * response whether or not the query asks it to, so past the cap the pages
 * showed an arbitrary slice — chosen by when a task was created, while the
 * calendar places by when it is due — and said nothing at all about it.
 *
 * These specs run against a deliberately tiny page size, so a dozen seeded
 * tasks reach the case that used to be invisible.
 */
test.skip(
  Boolean(process.env.BASE_URL),
  "needs the small-page server, which only the local config starts",
);

test.describe("more tasks than fit", () => {
  test("the count is the database's, not the page's", async ({ page }) => {
    await signIn(page, undefined, SMALL);
    await page.goto(`${SMALL}/tasks?filter=all`);

    // Relative, not absolute: the specs share one mock workspace and several
    // of them create tasks, so any exact total here would be true only when
    // this spec runs alone. What matters is that the total exceeds the page.
    const line = page.getByText(/\d+ of \d+/);
    await expect(line).toBeVisible({ timeout: 15_000 });

    const [shown, total] = (await line.innerText())
      .match(/(\d+) of (\d+)/)!
      .slice(1)
      .map(Number);

    expect(total).toBeGreaterThan(shown);
    // And it says so, rather than letting the page read as everything.
    await expect(page.getByText(/first 5/)).toBeVisible();
  });

  test("a filter chip counts every match, not just the ones on the page", async ({
    page,
  }) => {
    await signIn(page, undefined, SMALL);
    await page.goto(`${SMALL}/tasks?filter=all`);

    // The chip's number comes from the database function the dashboard tiles
    // use, so it can exceed the five rows this server will hand over. Before
    // this change it was computed from those five and could not.
    const pending = page.getByRole("link", { name: /Pending/ }).first();
    await expect(pending).toBeVisible({ timeout: 15_000 });

    const counted = Number((await pending.innerText()).match(/(\d+)/)![1]);
    expect(counted).toBeGreaterThan(5);
  });
});

/**
 * Desktop only: a phone's calendar square shows a count rather than titles,
 * which is deliberate — there is no room for a title in 50 pixels. The month
 * the browser holds is the same either way, so checking it once is enough.
 */
test.describe("the calendar asks for one month", () => {
  test.skip(({ isMobile }) => Boolean(isMobile), "squares show counts, not titles");

  test("turning to next month finds work that is there", async ({ page }) => {
    await signIn(page, undefined, SMALL);
    await page.goto(`${SMALL}/calendar?month=2026-09`);

    // Earliest in the window, so it is on the page whatever the page size.
    await expect(page.getByText("Sign the custody agreement")).toBeVisible({
      timeout: 15_000,
    });
    // October's task is not in September's window.
    await expect(page.getByText("October board meeting")).toHaveCount(0);
    // September holds more than this run's tiny page, and says so rather
    // than showing part of a month in silence.
    await expect(page.getByText("showing part of this month")).toBeVisible();

    await page.getByRole("button", { name: "Next month" }).click();

    // Fetched when the page was turned, not carried from the first render.
    await expect(page.getByText("October board meeting")).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText("Sign the custody agreement")).toHaveCount(0);
    // One task in October: a whole month, so nothing is held back.
    await expect(page.getByText("showing part of this month")).toHaveCount(0);
  });

  test("turning back is instant, because it is already held", async ({ page }) => {
    await signIn(page, undefined, SMALL);
    await page.goto(`${SMALL}/calendar?month=2026-09`);
    await expect(page.getByText("Sign the custody agreement")).toBeVisible({
      timeout: 15_000,
    });

    await page.getByRole("button", { name: "Next month" }).click();
    await expect(page.getByText("October board meeting")).toBeVisible({ timeout: 15_000 });

    await page.getByRole("button", { name: "Previous month" }).click();
    await expect(page.getByText("Sign the custody agreement")).toBeVisible({
      timeout: 5_000,
    });
  });

  test("the month stays in the address, so a reload lands on it", async ({ page }) => {
    await signIn(page, undefined, SMALL);
    await page.goto(`${SMALL}/calendar?month=2026-09`);
    await page.getByRole("button", { name: "Next month" }).click();
    await expect(page.getByText("October board meeting")).toBeVisible({ timeout: 15_000 });

    // The current month has a plain address and any other carries it — so
    // which of the two to expect depends on when this runs. It used to assume
    // October 2026 was in the future, and failed on the first of October.
    // Asked of the browser, because its zone is the one the app reads.
    const current = await page.evaluate(() =>
      new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit" })
        .format(new Date())
        .slice(0, 7),
    );
    const month = new URL(page.url()).searchParams.get("month");
    expect(month).toBe(current === "2026-10" ? null : "2026-10");

    await page.reload();
    await expect(page.getByText("October board meeting")).toBeVisible({ timeout: 15_000 });
  });
});
