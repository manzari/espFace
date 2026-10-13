import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  timeout: 90000,
  retries: 0,
  reporter: "list",
  use: {
    baseURL: process.env.E2E_BASE ?? "http://localhost:4173",
    viewport: { width: 420, height: 800 },
    hasTouch: true,
  },
});
