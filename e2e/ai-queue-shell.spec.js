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

  test("reorders queued cards with pointer drag and keeps the order after reload", async ({ page }, testInfo) => {
    const token = `${Date.now()}-${testInfo.retry}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_queue_reorder.rb", { E2E_TOKEN: token })

    await signIn(page, scenario.credentials)
    await page.goto(scenario.note_path)

    const dock = page.locator("[data-ai-review-target='queueDock']")
    await expect(dock).toBeVisible()

    const queueTitles = async () => {
      return await page.locator("[data-ai-review-target='queueDock'] article p:nth-of-type(2)").evaluateAll((nodes) =>
        nodes.map((node) => node.textContent.trim())
      )
    }

    const highCard = page.locator("[data-ai-review-target='queueDock'] article").filter({ hasText: scenario.titles.high }).first()
    const lowCard = page.locator("[data-ai-review-target='queueDock'] article").filter({ hasText: scenario.titles.low }).first()

    await expect(queueTitles()).resolves.toEqual([
      scenario.titles.high,
      scenario.titles.mid,
      scenario.titles.low
    ])

    const highBox = await highCard.boundingBox()
    const lowBox = await lowCard.boundingBox()
    if (!highBox || !lowBox) throw new Error("Queue cards not visible for pointer drag test")

    await page.mouse.move(highBox.x + (highBox.width / 2), highBox.y + (highBox.height / 2))
    await page.mouse.down()
    await page.mouse.move(lowBox.x + (lowBox.width / 2), lowBox.y + lowBox.height - 4, { steps: 12 })
    await page.mouse.up()

    await expect.poll(queueTitles).toEqual([
      scenario.titles.mid,
      scenario.titles.low,
      scenario.titles.high
    ])

    await page.reload()
    await expect(dock).toBeVisible()
    await expect.poll(queueTitles).toEqual([
      scenario.titles.mid,
      scenario.titles.low,
      scenario.titles.high
    ])
  })
})
