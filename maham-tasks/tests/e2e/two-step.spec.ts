import { expect, test, type Page } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * Two-step sign-in.
 *
 * The mock accepts "123456" as the code from any authenticator app and
 * nothing else. Huda has an app already; Priya sets one up here. Neither is
 * anybody the other specs sign in as, so what happens to them here cannot
 * reach another spec.
 *
 * What a half-signed-in session may do in the database is checked against a
 * real Postgres in supabase/tests/two-step.sql.
 */
const HUDA = { email: "huda@almailgroup.com", name: "Huda Saleh" };
const PRIYA = { email: "priya@almailgroup.com", name: "Priya Nair" };

async function passwordOnly(page: Page, who: { email: string }) {
  await page.goto("/login");
  await page.fill("#email", who.email);
  await page.fill("#password", "not-checked-by-the-mock");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL(/\/login\/verify/, { timeout: 30_000 });
}

const codeBox = (page: Page) => page.getByLabel("Six-digit code");

test.describe("signing in with an authenticator app", () => {
  test("the password is only half of it", async ({ page }) => {
    await passwordOnly(page, HUDA);
    await expect(page.getByRole("heading", { name: "Enter your code" })).toBeVisible();

    // Every page asks for the code until it has been given.
    await page.goto("/tasks?filter=all");
    await page.waitForURL(/\/login\/verify\?next=%2Ftasks%3Ffilter%3Dall/);

    // A wrong code says so, and empties the box for the next try.
    await codeBox(page).fill("000000");
    await expect(page.getByRole("alert").filter({ hasText: "That code did not match" })).toBeVisible();
    await expect(codeBox(page)).toHaveValue("");

    // The sixth digit sends it; the page it was going to comes next.
    await codeBox(page).fill("123456");
    await page.waitForURL(/\/tasks\?filter=all/);
    await expect(page.getByRole("heading", { name: "Enter your code" })).toHaveCount(0);
  });

  test("the code page sends anybody without a session back to sign in", async ({ page }) => {
    await page.goto("/login/verify?next=/today");
    await page.waitForURL(/\/login\?next=%2Ftoday/);
  });
});

test.describe("setting it up", () => {
  // Priya's account is shared by both projects in the run: one at a time.
  test.skip(() => test.info().project.name !== "desktop", "one copy of Priya's account");

  test("from Profile, then asked for at the next sign-in, then turned off", async ({ page }) => {
    await signIn(page, PRIYA);
    await page.goto("/profile");

    const card = page.locator("#two-step");
    await card.getByRole("button", { name: "Set up two-step sign-in" }).click();
    const qr = card.getByRole("img", { name: "QR code for your authenticator app" });
    await expect(qr).toBeVisible();
    // Drawn, not a broken-image box: a "#" left unencoded in the SVG's data
    // URL cuts it short in every browser.
    await expect
      .poll(() => qr.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth))
      .toBeGreaterThan(0);
    await expect(card.getByText("JBSWY3DPEHPK3PXP")).toBeVisible();
    // A desktop scans the QR code with a phone; only a phone is offered the
    // link that hands the key to its own authenticator.
    await expect(card.getByRole("link", { name: "Add to this phone" })).toBeHidden();

    await codeBox(page).fill("123456");
    await expect(page.getByText("Two-step sign-in is on.")).toBeVisible();
    await expect(card.getByText("On", { exact: true })).toBeVisible();

    // Signing in again now takes the code.
    await page.goto("/auth/signout");
    await page.waitForURL(/\/login/);
    await passwordOnly(page, PRIYA);
    await codeBox(page).fill("123456");
    await page.waitForURL(/\/dashboard/);

    // And off again, which also leaves the shared mock as it was.
    await page.goto("/profile");
    await card.getByRole("button", { name: "Turn off" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Turn off" }).click();
    await expect(page.getByText("Two-step sign-in is off.")).toBeVisible();
    await expect(card.getByRole("button", { name: "Set up two-step sign-in" })).toBeVisible();
  });
});

test("an admin without it is told, on the Team page, what it is needed for", async ({ page }) => {
  await signIn(page);
  await page.goto("/team");
  await expect(page.getByText("Turn on two-step sign-in to manage the team")).toBeVisible();
  await expect(page.getByRole("link", { name: "Set up two-step sign-in" })).toHaveAttribute(
    "href",
    "/profile#two-step",
  );
});
