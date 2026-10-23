import { expect, test } from "@playwright/test";

import { PEOPLE, signIn, unique } from "./helpers";

test.describe("private messages", () => {
  test("a thread can be opened and added to", async ({ page }) => {
    const line = unique("Approved — go ahead");

    await signIn(page);
    await page.goto("/messages");

    await page.getByText(PEOPLE.manager.name).first().click();
    await page.waitForURL(/\/messages\/[0-9a-f-]+/, { timeout: 15_000 });
    await expect(
      page.getByRole("log").getByText("Can you approve the custody agreement today?"),
    ).toBeVisible();

    const composer = page.getByRole("textbox").last();
    await composer.fill(line);
    await composer.press("Enter");

    // Scoped to the transcript: once sent, the same words also appear as the
    // preview on the conversation list beside it.
    const transcript = page.getByRole("log");
    await expect(transcript.getByText(line)).toBeVisible({ timeout: 15_000 });

    // Sent, not just drawn: it survives a reload.
    await page.reload();
    await expect(transcript.getByText(line)).toBeVisible({ timeout: 15_000 });
  });

  test("a thread that is not yours is not found", async ({ page }) => {
    // Opening somebody else's conversation and opening one that does not
    // exist look the same from outside, deliberately: a 404 either way
    // rather than a 403 that confirms the thread is real.
    //
    // The rule itself is row-level security, checked against a real Postgres.
    // What is checked here is that the app asks for the row and believes the
    // answer rather than deciding for itself.
    await signIn(page, PEOPLE.member);
    await page.goto("/messages/99999999-9999-4999-8999-000000000999");
    await expect(page.getByText(/could not be found|not found/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });
});
