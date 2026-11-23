import { expect, test } from "@playwright/test";

/**
 * `public/` was empty for the whole life of this project, so every tab showed
 * a blank document icon and the portal could not be installed to a phone.
 * These assert the icons and manifest stay wired up.
 */
test("serves a favicon, an apple touch icon and a manifest", async ({ request }) => {
  for (const asset of ["/icon.svg", "/apple-icon.png", "/manifest.webmanifest"]) {
    const response = await request.get(asset);
    expect(response.status(), `${asset} should be served`).toBe(200);
  }
});

test("the manifest describes an installable app", async ({ request }) => {
  const manifest = await (await request.get("/manifest.webmanifest")).json();
  expect(manifest.display).toBe("standalone");
  expect(manifest.start_url).toBe("/dashboard");
  expect(manifest.icons.length).toBeGreaterThanOrEqual(2);
  expect(manifest.icons.some((i: { purpose?: string }) => i.purpose === "maskable")).toBe(true);
});
