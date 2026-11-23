import { expect, test } from "@playwright/test";

import { PEOPLE, signIn } from "./helpers";

/**
 * A reminder that could not be delivered.
 *
 * It used to be marked failed in a table nobody reads, while somebody waited
 * to hear about work they never heard about. The seeded workspace holds one
 * such reminder, to the manager.
 *
 * What the database allows is checked against a real Postgres in
 * supabase/tests/reminder-failures.sql; these check that the interface shows
 * the right person the right thing.
 */
test.describe("delivery failures", () => {
  test("an admin sees the team's, beside the channels themselves", async ({ page }) => {
    await signIn(page);
    await page.goto("/profile");

    await expect(page.getByText("Some reminders could not be delivered")).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText("Across the team")).toBeVisible();
    await expect(page.getByText(/Sara Khan/)).toBeVisible();
    await expect(page.getByText(/WhatsApp/).first()).toBeVisible();
  });

  test("the message itself is never shown", async ({ page }) => {
    await signIn(page);
    await page.goto("/profile");
    await expect(page.getByText("Some reminders could not be delivered")).toBeVisible({
      timeout: 15_000,
    });

    // Who, which channel and why — not what the reminder said.
    await expect(page.getByText("Sign the custody agreement is due")).toHaveCount(0);
  });

  test("somebody with nothing wrong is shown nothing", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/profile");

    // The page has loaded — the reminder settings are on it — and the block
    // is simply absent rather than empty.
    await expect(page.getByText("Telegram").first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText("Some reminders could not be delivered")).toHaveCount(0);
  });

  test("and a member does not see the team's either", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/profile");

    await expect(page.getByText("Telegram").first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText("Across the team")).toHaveCount(0);
    await expect(page.getByText(/Sara Khan/)).toHaveCount(0);
  });
});

/**
 * Faults from the deployed app.
 *
 * Nothing used to capture these: a page that threw on somebody's phone left
 * a line in a log nobody reads. The seeded workspace holds one fault, seen
 * twice, reported by somebody who is not the admin.
 */
test.describe("the error log", () => {
  test("an admin sees what has been going wrong, grouped", async ({ page }) => {
    await signIn(page);
    await page.goto("/profile");

    await expect(page.getByText("Recent faults")).toBeVisible({ timeout: 15_000 });
    await expect(
      page.getByText("TypeError: Cannot read properties of null"),
    ).toBeVisible();
    // One fault seen twice is one line with a count, not two lines.
    await expect(page.getByText("2×")).toBeVisible();
  });

  test("nobody else does", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await page.goto("/profile");

    await expect(page.getByText("Telegram").first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText("Recent faults")).toHaveCount(0);
  });
});
