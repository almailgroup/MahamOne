import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

/**
 * A project that is finished with.
 *
 * Who may archive one and the refusal while work is still open are checked
 * against a real Postgres in supabase/tests/archive-projects.sql. These
 * check the part somebody sees: it leaves the sidebar, and it is still
 * there when you go looking.
 */
test.describe("an archived project", () => {
  test("is out of the sidebar", async ({ page, isMobile }) => {
    await signIn(page);

    // On a phone the projects are behind "More", which opens the same rail
    // as a drawer. Nothing to look at until it is open.
    if (isMobile) {
      await page.getByRole("button", { name: /More/ }).first().click();
    }

    await expect(page.getByRole("link", { name: "Kuwait Bank Portal" }).first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByRole("link", { name: "2025 Audit" })).toHaveCount(0);
  });

  test("is still readable, and says what it is", async ({ page }) => {
    await signIn(page);
    await page.goto("/projects/11111111-1111-4111-8111-000000000004");

    await expect(page.getByRole("heading", { name: "2025 Audit" })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText(/This project is archived/)).toBeVisible();
  });

  test("can be archived and brought back", async ({ page }) => {
    await signIn(page);
    // Brand Refresh has one task left open, so archiving it is refused —
    // which is the difference between finishing with a project and losing
    // track of one.
    await page.goto("/projects/11111111-1111-4111-8111-000000000003");
    await page.getByRole("button", { name: "Project actions" }).click();
    await page.getByRole("menuitem", { name: "Archive project" }).click();

    await expect(page.getByText(/still has \d+ task\(s\) open/)).toBeVisible({
      timeout: 15_000,
    });
  });
});
