import { expect, test } from "@playwright/test";

/**
 * /api/health, as an uptime monitor asks it: no session, no secret, and an
 * answer that says whether the database is there and the migrations run.
 */
test("the health check answers without signing in", async ({ request }) => {
  const response = await request.get("/api/health", { maxRedirects: 0 });
  expect(response.status()).toBe(200);
  expect(response.headers()["cache-control"]).toContain("no-store");
  expect(await response.json()).toMatchObject({ status: "ok", database: "ok", schema: 46, missing: [] });
});
