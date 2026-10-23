import { expect, test } from "@playwright/test";

import { openDialog, PEOPLE, signIn, taskNamed, unique } from "./helpers";

/**
 * The palette is the fastest way through the portal, so it has to know about
 * all of it. Every destination added to the sidebar since belongs here too,
 * which is the kind of thing that quietly stops being true.
 */
test.describe("the command palette", () => {
  test("knows every place the sidebar does", async ({ page }) => {
    await signIn(page);
    await page.keyboard.press("ControlOrMeta+k");
    const palette = await openDialog(page);

    for (const destination of [
      "Today",
      "Calendar",
      "My List",
      "General tasks",
      "Team",
      "Team chat",
      "Messages",
      "Settings",
    ]) {
      await palette.getByRole("textbox").fill(destination);
      await expect(
        palette.getByRole("listitem").filter({ hasText: destination }).first(),
      ).toBeVisible();
    }
  });

  test("finds a person, and opens the thread with them", async ({ page }) => {
    await signIn(page);
    await page.keyboard.press("ControlOrMeta+k");
    const palette = await openDialog(page);

    await palette.getByRole("textbox").fill("priya");
    const person = palette.getByRole("listitem").filter({ hasText: "Priya Nair" }).first();
    await expect(person).toBeVisible({ timeout: 10_000 });
    await expect(palette).toContainText("People");

    await person.click();
    await page.waitForURL(/\/messages\/[0-9a-f-]+/, { timeout: 15_000 });
    // The visible copy: on a phone the conversation list is still in the
    // page behind the thread, name and all.
    await expect(
      page.getByText("Priya Nair").filter({ visible: true }).first(),
    ).toBeVisible();
  });

  test("does not offer to message yourself", async ({ page }) => {
    await signIn(page, PEOPLE.manager);
    await page.keyboard.press("ControlOrMeta+k");
    const palette = await openDialog(page);

    await palette.getByRole("textbox").fill("Sara");
    await expect(
      palette.getByRole("listitem").filter({ hasText: "Sara Khan" }),
    ).toHaveCount(0);
  });

  test("finds what was said in the team room, and goes there", async ({ page }) => {
    await signIn(page);
    await page.keyboard.press("ControlOrMeta+k");
    const palette = await openDialog(page);

    await palette.getByRole("textbox").fill("moved to 3pm");
    const said = palette.getByRole("listitem").filter({ hasText: "moved to 3pm" }).first();
    await expect(said).toBeVisible({ timeout: 10_000 });
    await expect(palette).toContainText("Team chat");
    await said.click();
    await page.waitForURL(/\/chat$/);
  });

  test("finds a comment, and opens the task it is on", async ({ page }) => {
    const remark = unique("Bring the stamped letter");
    // A task of its own: a comment on a shared one would show up in every
    // other spec that opens it.
    const title = unique("Visit the ministry");

    await signIn(page);
    await page.goto("/general?new=1");
    const created = await openDialog(page);
    await created.locator("#title").fill(title);
    await created.getByRole("button", { name: "Create task" }).click();
    await expect(created).toBeHidden({ timeout: 15_000 });

    await page.goto("/tasks?filter=all");
    await taskNamed(page, title).click();
    const task = await openDialog(page);
    await task.getByLabel("New comment").fill(remark);
    await task.getByRole("button", { name: "Comment", exact: true }).click();
    await expect(task.getByText(remark)).toBeVisible();
    await page.keyboard.press("Escape");

    await page.keyboard.press("ControlOrMeta+k");
    const palette = await openDialog(page);
    await palette.getByRole("textbox").fill(remark);
    const found = palette.getByRole("listitem").filter({ hasText: remark }).first();
    await expect(found).toBeVisible({ timeout: 10_000 });
    await expect(found).toContainText(title);
    await expect(palette).toContainText("Comments");
    await found.click();
    await page.waitForURL(/task=/);
    await expect(page.getByRole("dialog").locator("#title")).toHaveValue(title);
  });
});
