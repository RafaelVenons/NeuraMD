const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test("typewriter keeps the native cursor visible in the centered editor", async ({ page }) => {
  page.on("pageerror", (error) => {
    console.log(`PAGEERROR: ${error.message}`)
  })
  page.on("console", (message) => {
    if (message.type() === "error") {
      console.log(`BROWSER_CONSOLE_ERROR: ${message.text()}`)
    }
  })

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
    const cursorRect = cursor?.getBoundingClientRect()
    const codemirrorHost = document.getElementById("codemirror-host")
    const hostRect = codemirrorHost?.getBoundingClientRect()

    return {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      stimulusControllers: window.Stimulus?.controllers?.map((controller) => controller.identifier) || [],
      editorZ: getComputedStyle(editorPane).zIndex,
      previewDisplay: getComputedStyle(previewPane).display,
      cursorBorderLeftColor: getComputedStyle(cursor).borderLeftColor,
      cursorBorderLeftWidth: getComputedStyle(cursor).borderLeftWidth,
      cursorLayerZ: getComputedStyle(cursorLayer).zIndex,
      cursorLayerTransform: getComputedStyle(cursorLayer).transform,
      cursorLeft: cursorRect?.left ?? null,
      cursorTop: cursorRect?.top ?? null,
      cursorRight: cursorRect?.right ?? null,
      cursorBottom: cursorRect?.bottom ?? null,
      hostLeft: hostRect?.left ?? null,
      hostRight: hostRect?.right ?? null,
      hostTop: hostRect?.top ?? null,
      hostBottom: hostRect?.bottom ?? null
    }
  })

  console.log(JSON.stringify(diagnostics, null, 2))

  expect(diagnostics.previewDisplay).toBe("none")
  expect(parseInt(diagnostics.cursorBorderLeftWidth, 10)).toBeGreaterThan(0)
  expect(diagnostics.cursorLeft).not.toBeNull()
  expect(diagnostics.cursorTop).not.toBeNull()
  expect(diagnostics.cursorRight).not.toBeNull()
  expect(diagnostics.cursorBottom).not.toBeNull()
  expect(diagnostics.cursorLeft).toBeGreaterThanOrEqual(0)
  expect(diagnostics.cursorTop).toBeGreaterThanOrEqual(0)
  expect(diagnostics.cursorRight).toBeLessThanOrEqual(diagnostics.viewportWidth)
  expect(diagnostics.cursorBottom).toBeLessThanOrEqual(diagnostics.viewportHeight)
  expect(diagnostics.cursorLeft).toBeGreaterThanOrEqual(diagnostics.hostLeft)
  expect(diagnostics.cursorRight).toBeLessThanOrEqual(diagnostics.hostRight)
  expect(diagnostics.cursorTop).toBeGreaterThanOrEqual(diagnostics.hostTop)
  expect(diagnostics.cursorBottom).toBeLessThanOrEqual(diagnostics.hostBottom)
})
