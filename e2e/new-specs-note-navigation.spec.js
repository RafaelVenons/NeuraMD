const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test.describe("new-specs note navigation", () => {
  test("opens an imported new-specs note and follows a sequential child link without server error", async ({ page }) => {
    const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
    const scenario = runRailsScript("script/e2e/bootstrap_new_specs_navigation.rb", { E2E_TOKEN: token })

    await signIn(page, scenario.credentials)

    const response = await page.goto(scenario.target_note_path, { waitUntil: "domcontentloaded" })
    expect(response).not.toBeNull()
    expect(response.ok()).toBeTruthy()

    await expect(page.locator("[data-editor-target='titleInput']")).toHaveValue(scenario.target_note_title)
    await expect(page.locator(".cm-editor")).toBeVisible()
    await expect(page.locator("body")).not.toContainText("We're sorry, but something went wrong.")
    await expect(page.locator("body")).not.toContainText("ActionController::RoutingError")

    await page.locator(".cm-content").click()
    await page.locator(".cm-content").pressSequentially(" ")
    await page.locator(".cm-content").press("Backspace")
    const childLink = page.locator(`a[href='${scenario.child_note_path}']`).first()
    await expect(childLink).toBeVisible()
    await Promise.all([
      page.waitForURL(new RegExp(`${scenario.child_note_path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`), { waitUntil: "domcontentloaded" }),
      childLink.click()
    ])
    await expect(page.locator("[data-editor-target='titleInput']")).toHaveValue(scenario.child_note_title)
    await expect(page.locator(".cm-editor")).toBeVisible()
    await expect(page.locator("body")).not.toContainText("We're sorry, but something went wrong.")
  })
})
