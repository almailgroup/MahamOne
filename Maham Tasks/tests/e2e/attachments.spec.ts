import { expect, test, type Locator, type Page } from "@playwright/test";

import { openDialog, signIn, taskNamed, unique } from "./helpers";

/**
 * Attaching files: picked, pasted, dropped, or photographed; pictures shown
 * as pictures and opened full size in the app.
 *
 * Who may read a file is decided in storage and checked against a real
 * Postgres in supabase/tests/attachment-files.sql; the mock stores whatever
 * it is sent.
 */

/** A 1×1 red PNG: small, and a real image a browser will draw. */
const PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==";

async function openFiles(page: Page) {
  const title = unique("Scan the signed contract");
  await page.goto("/general?new=1");
  const created = await openDialog(page);
  await created.locator("#title").fill(title);
  await created.getByRole("button", { name: "Create task" }).click();
  await expect(created).toBeHidden({ timeout: 15_000 });

  await page.goto("/tasks?filter=all");
  await taskNamed(page, title).click();
  const dialog = await openDialog(page);
  await dialog.getByRole("tab", { name: "Files" }).click();
  return dialog;
}

/** A clipboard or a drag carrying one picture, fired at `target`. */
async function deliver(target: Locator, kind: "paste" | "drop", name: string) {
  await target.evaluate(
    (element, { kind, name, png }) => {
      const bytes = Uint8Array.from(atob(png), (character) => character.charCodeAt(0));
      const transfer = new DataTransfer();
      transfer.items.add(new File([bytes], name, { type: "image/png" }));
      element.dispatchEvent(
        kind === "paste"
          ? new ClipboardEvent("paste", { clipboardData: transfer, bubbles: true, cancelable: true })
          : new DragEvent("drop", { dataTransfer: transfer, bubbles: true, cancelable: true }),
      );
    },
    { kind, name, png: PNG },
  );
}

const drawn = (image: Locator) =>
  image.evaluate((element: HTMLImageElement) => element.complete && element.naturalWidth);

test("a picked picture shows as a picture, and opens full size here", async ({ page }) => {
  await signIn(page);
  const dialog = await openFiles(page);

  await dialog.getByTestId("attach-files").setInputFiles({
    name: "receipt.png",
    mimeType: "image/png",
    buffer: Buffer.from(PNG, "base64"),
  });

  const row = dialog.getByRole("listitem").filter({ hasText: "receipt.png" });
  await expect(row).toBeVisible({ timeout: 15_000 });
  await expect.poll(() => drawn(row.locator("img"))).toBeGreaterThan(0);

  await row.getByRole("button", { name: /^receipt\.png/ }).click();
  const picture = page.getByRole("img", { name: "Picture: receipt.png" });
  await expect(picture).toBeVisible();
  await expect.poll(() => drawn(picture)).toBeGreaterThan(0);
});

test.describe("on a desktop", () => {
  test.skip(({ isMobile }) => isMobile, "a phone has no drop zone; it has the camera");

  test("a pasted screenshot is attached under a name that says what it is", async ({ page }) => {
    await signIn(page);
    const dialog = await openFiles(page);

    const zone = dialog.getByRole("button", { name: /paste a screenshot/ });
    await zone.click();
    await deliver(zone, "paste", "image.png");
    await expect(dialog.getByRole("listitem").filter({ hasText: /^Screenshot \d{4}-\d{2}-\d{2}/ })).toBeVisible({
      timeout: 15_000,
    });
  });

  test("a dropped file is attached", async ({ page }) => {
    await signIn(page);
    const dialog = await openFiles(page);

    await deliver(dialog.getByRole("button", { name: /paste a screenshot/ }), "drop", "site-photo.png");
    await expect(dialog.getByRole("listitem").filter({ hasText: "site-photo.png" })).toBeVisible({
      timeout: 15_000,
    });
  });

  test("the camera is not offered without one", async ({ page }) => {
    await signIn(page);
    const dialog = await openFiles(page);
    await expect(dialog.getByRole("button", { name: "Take photo" })).toBeHidden();
  });
});

test("a phone is offered its camera", async ({ page, isMobile }) => {
  test.skip(!isMobile, "the camera button is for phones");
  await signIn(page);
  const dialog = await openFiles(page);
  await expect(dialog.getByRole("button", { name: "Take photo" })).toBeVisible();
});
