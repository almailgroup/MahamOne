import { expect, test } from "@playwright/test";

import { PEOPLE, signIn } from "./helpers";

/**
 * The first-day guide on the dashboard: a short list for each kind of
 * account, ticking itself where the app can tell, put away with one tap and
 * brought back from Search.
 */

test("a member gets four steps, ticks one from the guide, and puts it away", async ({ page }) => {
  await signIn(page, PEOPLE.member);
  const guide = page.getByRole("region", { name: "Getting started" });
  await expect(guide).toBeVisible();
  await expect(guide.getByRole("listitem")).toHaveCount(4);
  await expect(guide).toContainText("Move your work along");
  // Running the office is not a member's list.
  await expect(guide).not.toContainText("Add your team");
  await expect(guide.getByRole("meter", { name: "0 of 4 done" })).toBeVisible();

  // "Try it" opens Search itself, and counts as done.
  await guide.getByRole("button", { name: "Try it" }).click();
  await expect(page.getByRole("dialog").getByRole("combobox").or(page.getByRole("dialog").getByRole("textbox")).first()).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(guide.getByRole("meter", { name: "1 of 4 done" })).toBeVisible();

  await guide.getByRole("button", { name: "Hide the guide" }).click();
  await expect(guide).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(guide).toHaveCount(0);

  // Search brings it back, with what was done still done.
  await page.goto("/dashboard?guide=1");
  await expect(guide.getByRole("meter", { name: "1 of 4 done" })).toBeVisible();
});

test("an admin's guide is about setting the office up, and ticks what is already done", async ({ page }) => {
  await signIn(page, PEOPLE.admin);
  const guide = page.getByRole("region", { name: "Getting started" });
  await expect(guide).toBeVisible();

  const step = (title: string) => guide.getByRole("listitem").filter({ hasText: title });
  await expect(step("Turn on two-step sign-in")).toContainText("Not done yet");
  await expect(step("Turn on two-step sign-in").getByRole("link", { name: "Set it up" })).toHaveAttribute(
    "href",
    "/profile#two-step",
  );
  // There are people on the team and projects on the go already.
  await expect(step("Add your team")).toContainText("Done");
  await expect(step("Start a project")).toContainText("Done");
  // Somebody else's list.
  await expect(guide).not.toContainText("Move your work along");
});
