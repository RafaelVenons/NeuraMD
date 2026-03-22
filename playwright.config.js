const { defineConfig } = require("@playwright/test")

const useExternalServer = process.env.PLAYWRIGHT_NO_WEBSERVER === "1"

module.exports = defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 90_000,
  expect: {
    timeout: 10_000
  },
  reporter: [
    ["list"],
    ["html", { open: "never", outputFolder: "playwright-report" }]
  ],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://127.0.0.1:3101",
    headless: process.env.HEADED !== "1",
    viewport: { width: 1440, height: 1000 },
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure",
    launchOptions: {
      executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH || "/usr/bin/chromium",
      args: ["--no-sandbox", "--disable-setuid-sandbox"]
    }
  },
  webServer: useExternalServer ? undefined : {
    command: "RAILS_ENV=test ACTIVE_JOB_QUEUE_ADAPTER=test bin/rails server -b 127.0.0.1 -p 3101",
    url: "http://127.0.0.1:3101/users/sign_in",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
})
