import { defineConfig, devices } from "@playwright/test";

/*
  One end-to-end spec against `next dev` with the in-memory waitlist backend
  (ALLOW_INMEM=1, no DATABASE_URL). See SPEC.md §12.
*/
export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: true,
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: { ALLOW_INMEM: "1", DATABASE_URL: "" },
  },
});
