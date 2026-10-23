import { expect, test } from "@playwright/test";

import { signIn, unique } from "./helpers";

/**
 * The unread count beside Messages in the rail.
 *
 * It is a plain number, read once by the app's layout, and nothing on the
 * client subscribes to it — unlike the notification bell, which has its own
 * realtime channel. So the only thing that can move it is the layout being
 * rendered again, and the only thing that causes that is whichever Server
 * Action changed what it counts invalidating the right path.
 *
 * `markConversationRead` invalidates `/messages` while the thread itself
 * lives at `/messages/<id>`, which looks like it should not be enough. It is:
 * an action that revalidates anything re-renders the tree it was called from.
 * Pinned here because that is a fact about the framework rather than about
 * this code, and the failure if it ever stops being true is silent — a badge
 * sitting at 3 while you read the messages it is counting.
 *
 * Desktop only: on a phone the rail is inside a drawer behind "More".
 */
test.describe("the messages badge", () => {
  // A pair nothing else in the run writes to, so the number asserted here is
  // only ever this spec's doing.
  const LINA = { email: "lina@almailgroup.com", name: "Lina Aboud" };
  const YUSUF = { email: "yusuf@almailgroup.com", name: "Yusuf Rahman" };

  test.skip(({ viewport }) => (viewport?.width ?? 0) < 1024, "needs the rail");

  test("clears when the thread is read, without a reload", async ({ page }) => {
    const line = unique("Signage quote attached");

    // --- lina writes to yusuf ---------------------------------------------
    await signIn(page, LINA);
    await page.goto("/messages");
    await page.getByRole("button", { name: "New message" }).first().click();
    await page.getByText(YUSUF.name).first().click();
    await page.waitForURL(/\/messages\/[0-9a-f-]+/, { timeout: 15_000 });

    // By name, not "the last textbox": the people picker's search field is
    // still in the DOM behind the closed dialog and answers that just as well.
    const composer = page.getByRole("textbox", {
      name: new RegExp(`^Message ${YUSUF.name.split(" ")[0]}`),
    });
    await composer.fill(line);
    await composer.press("Enter");
    await expect(page.getByRole("log").getByText(line)).toBeVisible({
      timeout: 15_000,
    });

    // --- yusuf arrives to one unread --------------------------------------
    await page.goto("/auth/signout");
    await signIn(page, YUSUF);

    const rail = page.getByRole("navigation").first();
    const messages = rail.getByRole("link", { name: /Messages/ });
    await expect(messages).toContainText("1", { timeout: 15_000 });

    // --- he reads it ------------------------------------------------------
    await messages.click();
    // Wait for the list, and click the conversation as a link. By text alone
    // this raced the navigation: the dashboard is still on screen for a
    // moment after the click, Lina's name is on it (in the workload card),
    // and `.first()` took that button instead of her thread.
    await page.waitForURL(/\/messages$/, { timeout: 15_000 });
    await page.getByRole("link", { name: new RegExp(LINA.name) }).click();
    await page.waitForURL(/\/messages\/[0-9a-f-]+/, { timeout: 15_000 });
    await expect(page.getByRole("log").getByText(line)).toBeVisible({
      timeout: 15_000,
    });

    // Reading is what clears it. No reload: a reload would pass whether or
    // not the action invalidated anything, which is the whole question.
    await expect(messages).not.toContainText("1", { timeout: 15_000 });
  });
});
