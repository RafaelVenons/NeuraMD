const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")

async function signIn(page, credentials) {
  await page.goto("/users/sign_in")
  await page.getByLabel("E-mail").fill(credentials.email)
  await page.getByLabel("Senha").fill(credentials.password)
  await page.getByRole("button", { name: "Entrar" }).click()
  await expect(page).toHaveURL(/\/graph/)
}

test.describe("AI queue shell", () => {
  test("shows queue and shell history consistently for seeded promise states", async ({ page }, testInfo) => {
    const token = `${Date.now()}-${testInfo.retry}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_queue.rb", { E2E_TOKEN: token })

    await signIn(page, scenario.credentials)
    await page.goto(scenario.note_path)

    await expect(page.locator(".cm-editor")).toBeVisible()
    await expect(page.locator("[data-ai-review-target='queueDock']")).toBeVisible()

    for (const card of scenario.queue_cards) {
      await expect(page.locator("[data-ai-review-target='queueDock']")).toContainText(card.title)
      await expect(page.locator("[data-ai-review-target='queueDock']")).toContainText(card.status_label)
    }

    await page.screenshot({
      path: testInfo.outputPath("01-queue.png"),
      fullPage: true
    })

    await page.getByRole("button", { name: "Histórico de IA" }).click()
    await expect(page.locator("[data-ai-review-target='historyDialog']")).toBeVisible()
    await page.getByRole("button", { name: "Shell" }).click()

    for (const card of scenario.queue_cards) {
      await expect(page.locator("[data-ai-review-target='historyList']")).toContainText(card.title)
    }

    await page.screenshot({
      path: testInfo.outputPath("02-history-shell.png"),
      fullPage: true
    })

    await page.locator("[data-ai-review-target='historyDialog']").locator(`[data-request-id="${scenario.completed_seed_request_id}"]`).first().click()
    await expect(page).toHaveURL(new RegExp(`${scenario.created_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`))
    await expect(page.locator("[data-ai-review-target='workspace']")).toBeVisible()

    await page.screenshot({
      path: testInfo.outputPath("03-open-completed-seed-note.png"),
      fullPage: true
    })
  })
})
