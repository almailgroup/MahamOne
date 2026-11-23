import { expect, test, type Browser, type Page } from "@playwright/test";

import { openDialog, PEOPLE, signIn, unique } from "./helpers";

/**
 * Swiping a task card on a phone: towards the end of the line moves the work
 * on, towards the start puts it off to the next working day, and either can
 * be undone. The gesture is a real one — touches sent through the browser,
 * so `touch-action` and the scroll-or-swipe decision are exercised too.
 */
test.skip(({ isMobile }) => !isMobile, "the cards, and the swipe, are the phone's layout");

async function newTask(browser: Browser, title: string) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await signIn(page, PEOPLE.manager);
  await page.goto("/general?new=1");
  const dialog = await openDialog(page);
  await dialog.locator("#title").fill(title);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });
  await context.close();
}

function card(page: Page, title: string) {
  return page.locator("[data-swipe-card]").filter({ hasText: title, visible: true }).first();
}

/** A finger across the card, `distance` pixels to the right (negative: left). */
async function swipe(page: Page, title: string, distance: number) {
  // Mid-screen: touches are sent to a point, and the bottom bar covers the
  // last stretch of the page.
  await card(page, title).evaluate((element) => element.scrollIntoView({ block: "center" }));
  const box = await card(page, title).boundingBox();
  if (!box) throw new Error(`no card for ${title}`);
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
  for (let step = 1; step <= 10; step++) {
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: x + (distance * step) / 10, y }],
    });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await cdp.detach();
}

test("a planner swipes a task done, and takes it back", async ({ page, browser }) => {
  const title = unique("Swipe me done");
  await newTask(browser, title);

  await signIn(page, PEOPLE.manager);
  await page.goto("/tasks?filter=all");
  await expect(card(page, title)).toContainText("To Do");

  await swipe(page, title, 200);
  const toast = page.getByText(`${title}: now Done`);
  await expect(toast).toBeVisible();
  await expect(card(page, title)).toContainText("Done");
  // The swipe was not also a tap: the task did not open.
  await expect(page.getByRole("dialog")).toHaveCount(0);

  await page.getByRole("button", { name: "Undo" }).click();
  await expect(card(page, title)).toContainText("To Do");
});

test("a planner swipes a task to the next working day", async ({ page, browser }) => {
  const title = unique("Swipe me later");
  await newTask(browser, title);

  await signIn(page, PEOPLE.manager);
  await page.goto("/tasks?filter=all");
  await expect(card(page, title).getByTitle("Due date")).toHaveCount(0);

  await swipe(page, title, -200);
  await expect(page.getByText(/^Moved to /)).toBeVisible();
  await expect(card(page, title).getByTitle("Due date")).toBeVisible();

  await page.getByRole("button", { name: "Undo" }).click();
  await expect(card(page, title).getByTitle("Due date")).toHaveCount(0);
});

test("a short swipe does nothing, and a member's swipe starts work but never dates it", async ({
  page,
  browser,
}) => {
  const title = unique("Swipe me started");
  await newTask(browser, title);

  await signIn(page, PEOPLE.member);
  await page.goto("/tasks?filter=all");

  // Not far enough: back where it was, nothing done.
  await swipe(page, title, 60);
  await expect(card(page, title)).toContainText("To Do");

  // A member does not set dates, so the card does not move that way at all.
  await swipe(page, title, -200);
  await expect(page.getByText(/^Moved to /)).toHaveCount(0);

  await swipe(page, title, 200);
  await expect(page.getByText(`${title}: now In Progress`)).toBeVisible();
  await expect(card(page, title)).toContainText("In Progress");
});

test("a finger dragged up a card still scrolls the list", async ({ page }) => {
  await signIn(page, PEOPLE.manager);
  // Open work only: a finished task has nothing to swipe to, and so leaves
  // touches to the browser anyway.
  await page.goto("/tasks?filter=todo");
  const first = page.locator("[data-swipe-card]").filter({ visible: true }).first();
  await expect(first).toHaveClass(/touch-pan-y/);
  await expect(first).toBeVisible();

  const box = await first.boundingBox();
  if (!box) throw new Error("no card");
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  const before = await page.evaluate(() => window.scrollY);

  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
  for (let step = 1; step <= 10; step++) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: x + step, y: y - step * 25 }] });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await cdp.detach();

  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(before + 100);
  await expect(page.getByText(/: now /)).toHaveCount(0);
});
