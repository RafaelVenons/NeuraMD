const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test("typewriter keeps the cursor above the preview overlay", async ({ page }) => {
  const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
  const scenario = runRailsScript("script/e2e/bootstrap_typewriter_cursor_visibility.rb", { E2E_TOKEN: token })

  await signIn(page, scenario.credentials)
  await page.goto(scenario.note_path)
  await expect(page.locator(".cm-editor")).toBeVisible()

  await page.locator(".cm-content").click()
  await page.keyboard.press("Control+\\")
  await expect(page.locator("body")).toHaveClass(/typewriter-mode/)

  const diagnostics = await page.evaluate(() => {
    const editorPane = document.getElementById("editor-pane")
    const previewPane = document.getElementById("preview-pane")
    const cursor = document.querySelector(".cm-cursor")
    const cursorLayer = document.querySelector(".cm-cursorLayer")

    return {
      editorZ: getComputedStyle(editorPane).zIndex,
      previewZ: getComputedStyle(previewPane).zIndex,
      cursorBorderLeftColor: getComputedStyle(cursor).borderLeftColor,
      cursorBorderLeftWidth: getComputedStyle(cursor).borderLeftWidth,
      cursorLayerZ: getComputedStyle(cursorLayer).zIndex
    }
  })

  console.log(JSON.stringify(diagnostics, null, 2))

  expect(Number(diagnostics.editorZ)).toBeGreaterThan(Number(diagnostics.previewZ))
  expect(Number(diagnostics.cursorLayerZ)).toBeGreaterThan(Number(diagnostics.previewZ))
  expect(parseInt(diagnostics.cursorBorderLeftWidth, 10)).toBeGreaterThan(0)
})
