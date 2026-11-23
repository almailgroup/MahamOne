import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end checks against a real build.
 *
 * The signed-out pages need no backend. The signed-in ones run against
 * `tests/mock/supabase.mjs`, a small stand-in that answers like PostgREST and
 * GoTrue and keeps what it is told, so a spec can create a task and then find
 * it. It enforces nothing: row-level security is verified against a real
 * Postgres, never here, and the production project is never a test target.
 *
 * Point BASE_URL at a deployment to run the same specs against it instead.
 */
const PORT = Number(process.env.PORT ?? 3210);
const MOCK_PORT = Number(process.env.MOCK_PORT ?? 54997);
/**
 * A second copy of the same build, with a deliberately tiny page size.
 *
 * The truncated case is the one that used to be silent, so it has to be
 * exercised — but a small page size across the whole suite would starve
 * every other spec of the rows it looks for. One more `next start` against
 * the same build is cheaper than seeding five hundred tasks.
 */
const SMALL_PORT = Number(process.env.SMALL_PORT ?? PORT + 1);
const baseURL = process.env.BASE_URL ?? `http://127.0.0.1:${PORT}`;
const mockURL = `http://127.0.0.1:${MOCK_PORT}`;
const smallURL = `http://127.0.0.1:${SMALL_PORT}`;

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL,
    trace: "on-first-retry",
    // Sandboxes that ship their own Chromium set this rather than letting
    // Playwright download a build it has pinned to its own version. CI leaves
    // it unset and uses `playwright install`.
    launchOptions: process.env.PLAYWRIGHT_CHROMIUM_PATH
      ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH }
      : {},
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["Pixel 7"] } },
  ],
  // Reuse an already-running server locally; start both in CI.
  webServer: process.env.BASE_URL
    ? undefined
    : [
        {
          command: "node tests/mock/supabase.mjs",
          url: `${mockURL}/__db`,
          reuseExistingServer: !process.env.CI,
          timeout: 30_000,
          env: { PORT: String(MOCK_PORT), MOCK_QUIET: "1" },
        },
        {
          // Built here, not beforehand: `NEXT_PUBLIC_*` is inlined into the
          // browser bundle at build time, so a build made against a real
          // project would keep talking to it however this is started.
          command: `npx next build && npx next start -p ${PORT}`,
          url: baseURL,
          reuseExistingServer: !process.env.CI,
          timeout: 300_000,
          env: {
            NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL ?? mockURL,
            NEXT_PUBLIC_SUPABASE_ANON_KEY:
              process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "test-anon-key",
            NEXT_PUBLIC_SITE_URL: baseURL,
          },
        },
        {
          // Same build, one env var different. `next build` has already run
          // by the time this starts, so it costs a process rather than a
          // compile.
          command: `npx next start -p ${SMALL_PORT}`,
          url: smallURL,
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
          env: {
            NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL ?? mockURL,
            NEXT_PUBLIC_SUPABASE_ANON_KEY:
              process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "test-anon-key",
            NEXT_PUBLIC_SITE_URL: smallURL,
            TASK_PAGE_SIZE: "5",
          },
        },
      ],
});
