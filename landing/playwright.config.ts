import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.PORT ?? 3000);
const baseURL = `http://127.0.0.1:${port}`;

/*
  One end-to-end spec against `next dev` with the in-memory waitlist backend
  (ALLOW_INMEM=1, no DATABASE_URL). See SPEC.md §12.
*/
export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: true,
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `./node_modules/.bin/next dev --hostname 127.0.0.1 --port ${port}`,
    url: baseURL,
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER === "1" || !process.env.CI,
    timeout: 120_000,
    env: { ALLOW_INMEM: "1", DATABASE_URL: "" },
  },
});
