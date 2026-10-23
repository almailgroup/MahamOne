import { expect, test } from "@playwright/test";

import { PEOPLE, signIn, unique } from "./helpers";

/**
 * Saying how a project is going, and the dashboard noticing.
 *
 * Who may post is row-level security's business, and is tested where it
 * lives — supabase/tests/project-status.sql, against a real Postgres. What is
 * checked here is the interface around it: an update can be written, it is
 * there after a reload, and a project called off track rises to the top of
 * the dashboard.
 *
 * The desktop and phone runs go in parallel against one shared workspace, so
 * each takes a project of its own. Two runs posting to the same project would
 * each find the other's update on top of theirs.
 */
const PROJECTS = {
  desktop: { id: "11111111-1111-4111-8111-000000000003", name: "Brand Refresh" },
  mobile: { id: "11111111-1111-4111-8111-000000000001", name: "Kuwait Bank Portal" },
} as const;

test.describe("project status", () => {
  test("an update is posted, kept, and flagged on the dashboard", async ({ page }, info) => {
    const project = PROJECTS[info.project.name as keyof typeof PROJECTS];
    const words = unique("Customs are holding the signage shipment");

    await signIn(page);
    await page.goto(`/projects/${project.id}`);

    const status = page.getByRole("region", { name: "Status" });
    await status.getByRole("button", { name: "Post update" }).click();
    await status.getByRole("radio", { name: "Off track" }).click();
    await status.getByRole("textbox").fill(words);
    await status.getByRole("button", { name: "Post", exact: true }).click();

    // The form closing is what says it saved: while it is open, the words
    // and the "Off track" choice are both on screen whether or not it did.
    await expect(status.getByRole("radiogroup")).toHaveCount(0, { timeout: 15_000 });
    await expect(status.getByText(words)).toBeVisible();
    await expect(status.getByText("Off track")).toBeVisible();

    // Kept, not just drawn.
    await page.reload();
    await expect(page.getByRole("region", { name: "Status" }).getByText(words)).toBeVisible({
      timeout: 15_000,
    });

    // And the dashboard puts it in front of whoever reports on projects.
    await page.goto("/dashboard");
    const attention = page.locator("a", { hasText: project.name }).filter({ hasText: words });
    await expect(attention).toBeVisible({ timeout: 15_000 });
    await expect(attention.getByText("Off track")).toBeVisible();
  });

  test("a member reads how it is going but is not offered to report on it", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    // Warehouse Move carries a seeded update its manager posted.
    await page.goto("/projects/11111111-1111-4111-8111-000000000002");

    const status = page.getByRole("region", { name: "Status" });
    await expect(status.getByText("At risk").first()).toBeVisible({ timeout: 15_000 });
    await expect(status.getByRole("button", { name: "Post update" })).toHaveCount(0);
  });

  test("a member's dashboard does not report on projects", async ({ page }) => {
    await signIn(page, PEOPLE.member);
    await expect(page.getByText("Projects needing attention")).toHaveCount(0);
  });
});
