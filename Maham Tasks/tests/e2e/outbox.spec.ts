import { expect, test, type Browser } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * Working through a dropped connection.
 *
 * With no signal, moving a task along and commenting are kept on the phone,
 * shown as done, and sent when the connection is back. These go offline for
 * real — the browser's own switch, so `navigator.onLine` and the failed
 * requests are both what a phone in a lift would see.
 */

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

test("a task moved with no signal is kept, then sent when it returns", async ({ page, context, browser, isMobile }) => {
  test.skip(!isMobile, "moved by a swipe, the phone's way");
  const title = unique("Moved in the lift");
  await newTask(browser, title);

  await signIn(page, PEOPLE.manager);
  await page.goto("/tasks?filter=all");
  const card = page.locator("[data-swipe-card]").filter({ hasText: title, visible: true }).first();
  await expect(card).toContainText("To Do");

  await context.setOffline(true);
  await expect(page.getByText("Offline — moves, ticks and comments are kept")).toBeVisible();

  // Pointer events from inside the page, not touches through a DevTools
  // session: in the headless browser CI uses, opening one quietly undoes
  // the offline switch, and the move went out before it could be kept.
  // The real-touch swipe itself is covered in swipe.spec.ts.
  await card.evaluate((element) => {
    element.scrollIntoView({ block: "center" });
    const box = element.getBoundingClientRect();
    const y = box.top + box.height / 2;
    const x = box.left + box.width / 2;
    const fire = (type: string, dx: number) =>
      element.dispatchEvent(
        new PointerEvent(type, {
          pointerId: 41,
          pointerType: "touch",
          isPrimary: true,
          clientX: x + dx,
          clientY: y,
          bubbles: true,
        }),
      );
    fire("pointerdown", 0);
    for (let step = 1; step <= 10; step++) fire("pointermove", step * 20);
    fire("pointerup", 200);
  });

  await expect(page.getByText("Kept on this phone. It will be sent when you are back online.")).toBeVisible();
  await expect(card).toContainText("Done");
  await expect(card).toContainText("Waiting to send");
  await expect(page.getByText("Offline — 1 change waiting to send")).toBeVisible();

  await context.setOffline(false);
  await expect(page.getByText("Sent 1 change made offline")).toBeVisible({ timeout: 15_000 });
  await expect(card).not.toContainText("Waiting to send");

  // On the server, not only on this phone.
  await page.reload();
  await expect(
    page.locator("[data-swipe-card]").filter({ hasText: title, visible: true }).first(),
  ).toContainText("Done");
});

test("a comment written with no signal waits in the thread, then posts", async ({ page, context, browser }) => {
  const title = unique("Commented in the lift");
  const words = unique("Signed copy is in the drawer");
  await newTask(browser, title);

  await signIn(page, PEOPLE.manager);
  await page.goto("/tasks?filter=all");
  await taskNamed(page, title).click();
  const dialog = await openDialog(page);
  await expect(dialog.getByText("No comments yet")).toBeVisible({ timeout: 15_000 });

  await context.setOffline(true);
  await dialog.getByPlaceholder("Write a comment. Use @ to mention someone.").fill(words);
  await dialog.getByRole("button", { name: "Comment", exact: true }).click();

  await expect(page.getByText("Kept on this phone. It will be sent when you are back online.")).toBeVisible();
  await expect(dialog.getByText(words)).toBeVisible();
  await expect(dialog.getByText("Waiting to send")).toBeVisible();
  await expect(page.getByText("Offline — 1 change waiting to send")).toBeVisible();

  await context.setOffline(false);
  await expect(page.getByText("Sent 1 change made offline")).toBeVisible({ timeout: 15_000 });
  await expect(dialog.getByText("Waiting to send")).toHaveCount(0);

  // And it is a real comment now: there after closing and opening again.
  await page.keyboard.press("Escape");
  await page.reload();
  await taskNamed(page, title).click();
  const again = await openDialog(page);
  await expect(again.getByText(words)).toBeVisible({ timeout: 15_000 });
});

test("the task form says it needs a connection, and keeps what was typed", async ({ page, context }) => {
  const title = unique("Typed in the lift");

  await signIn(page, PEOPLE.manager);
  await page.goto("/general?new=1");
  const dialog = await openDialog(page);
  await dialog.locator("#title").fill(title);

  await context.setOffline(true);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog.getByRole("alert").filter({ hasText: "This needs a connection." })).toBeVisible();
  await expect(dialog.locator("#title")).toHaveValue(title);
  await expect(dialog.getByRole("button", { name: "Create task" })).toBeEnabled();

  // Back online, the same press saves it.
  await context.setOffline(false);
  await dialog.getByRole("button", { name: "Create task" }).click();
  await expect(dialog).toBeHidden({ timeout: 15_000 });
});
