const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

async function openHistoryRequest(page, requestId) {
  await page.getByRole("button", { name: "Histórico de IA" }).click()
  const historyDialog = page.locator("[data-ai-review-target='historyDialog']")
  await expect(historyDialog).toBeVisible()
  await historyDialog.locator(`[data-request-id="${requestId}"]`).first().click()
}

test.describe("AI request navigation", () => {
  test("routes each completed capability to the correct note instead of the currently open one", async ({ page }) => {
    const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_request_navigation.rb", { E2E_TOKEN: token })

    await signIn(page, scenario.credentials)

    await page.goto(scenario.current_note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await openHistoryRequest(page, scenario.requests.rewrite)
    await expect(page).toHaveURL(new RegExp(`${scenario.source_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`))
    await expect(page.locator("[data-ai-review-target='workspace']")).toBeVisible()
    await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText(scenario.outputs.rewrite)

    await page.goto(scenario.current_note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await openHistoryRequest(page, scenario.requests.grammar_review)
    await expect(page).toHaveURL(new RegExp(`${scenario.source_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`))
    await expect(page.locator("[data-ai-review-target='workspace']")).toBeVisible()
    await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText(scenario.outputs.grammar_review)

    await page.goto(scenario.current_note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await openHistoryRequest(page, scenario.requests.translate)
    await expect(page).toHaveURL(new RegExp(`${scenario.translated_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`))
    await expect(page.locator("[data-editor-target='titleInput']")).toHaveValue(scenario.titles.translated)
    await expect(page.locator("[data-ai-review-target='workspace']")).toBeHidden()

    await page.goto(scenario.current_note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await openHistoryRequest(page, scenario.requests.seed_note)
    await expect(page).toHaveURL(new RegExp(`${scenario.promise_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`))
    await expect(page.locator("[data-ai-review-target='workspace']")).toBeVisible()
    await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText(scenario.outputs.seed_note)
  })
})
