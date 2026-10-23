import { expect, test } from "@playwright/test";

test.describe("password field", () => {
  test("can be read back, and hidden again", async ({ page }) => {
    await page.goto("/login");
    const field = page.locator("#password");
    await field.fill("hunter2-secret");

    await expect(field).toHaveAttribute("type", "password");
    await page.getByRole("button", { name: "Show password" }).click();
    await expect(field).toHaveAttribute("type", "text");
    // Toggling must not disturb what was typed.
    await expect(field).toHaveValue("hunter2-secret");

    await page.getByRole("button", { name: "Hide password" }).click();
    await expect(field).toHaveAttribute("type", "password");
  });

  test("the toggle stays out of the way of the keyboard", async ({ page }) => {
    // Tab from the password should reach Sign in, not the eye button — the
    // toggle is for the mouse and for touch, and interrupting the tab order
    // to sign in would be a poor trade.
    await page.goto("/login");
    await page.focus("#password");
    await page.keyboard.press("Tab");
    await expect(page.locator(":focus")).toHaveText(/Sign in/);
  });
});

test.describe("forgotten password", () => {
  test("is reachable from the sign-in page", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("link", { name: "Forgot password?" }).click();
    await page.waitForURL(/\/forgot-password/);
    await expect(page.getByRole("heading", { name: "Reset your password" })).toBeVisible();
  });

  test("says the same thing whether or not the account exists", async ({ page }) => {
    // The confirmation must not become an oracle for which company addresses
    // are registered.
    await page.goto("/forgot-password");
    await page.fill("#email", "definitely-not-a-user@nowhere.test");
    await page.getByRole("button", { name: "Email me a link" }).click();
    await expect(page.getByText("Check your email")).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(/If an account exists/)).toBeVisible();
  });

  test("offers a way back to sign in", async ({ page }) => {
    await page.goto("/forgot-password");
    await page.getByRole("link", { name: "Back to sign in" }).click();
    await page.waitForURL(/\/login/);
  });
});

test("the reset page cannot be opened without a link", async ({ page }) => {
  // The recovery email signs you in first; arriving any other way has no
  // session, and the middleware sends it to sign in.
  await page.goto("/reset-password");
  await page.waitForURL(/\/login/);
});
