const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test("typewriter keeps the cursor above the preview overlay", async ({ page }) => {
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
    const visualCursor = document.querySelector(".typewriter-visual-cursor")
    const cursorRect = visualCursor?.getBoundingClientRect() || cursor?.getBoundingClientRect()
    const previewText = document.querySelector(".preview-prose p, .preview-prose h2, .preview-prose h1")
    const previewRect = previewText?.getBoundingClientRect()
    const previewProse = document.querySelector(".preview-prose")
    const previewProseRect = previewProse?.getBoundingClientRect()

    return {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      stimulusControllers: window.Stimulus?.controllers?.map((controller) => controller.identifier) || [],
      editorZ: getComputedStyle(editorPane).zIndex,
      previewZ: getComputedStyle(previewPane).zIndex,
      cursorBorderLeftColor: getComputedStyle(cursor).borderLeftColor,
      cursorBorderLeftWidth: getComputedStyle(cursor).borderLeftWidth,
      cursorLayerZ: getComputedStyle(cursorLayer).zIndex,
      cursorLayerTransform: getComputedStyle(cursorLayer).transform,
      visualCursorDisplay: visualCursor ? getComputedStyle(visualCursor).display : null,
      cursorLeft: cursorRect?.left ?? null,
      cursorTop: cursorRect?.top ?? null,
      cursorRight: cursorRect?.right ?? null,
      cursorBottom: cursorRect?.bottom ?? null,
      previewLeft: previewRect?.left ?? null,
      previewTop: previewRect?.top ?? null,
      previewProseLeft: previewProseRect?.left ?? null,
      previewProseRight: previewProseRect?.right ?? null,
      previewProseTop: previewProseRect?.top ?? null,
      previewProseBottom: previewProseRect?.bottom ?? null
    }
  })

  console.log(JSON.stringify(diagnostics, null, 2))

  expect(Number(diagnostics.previewZ)).toBeGreaterThan(Number(diagnostics.editorZ))
  expect(Number(diagnostics.cursorLayerZ)).toBeGreaterThan(Number(diagnostics.previewZ))
  expect(parseInt(diagnostics.cursorBorderLeftWidth, 10)).toBeGreaterThan(0)
  expect(diagnostics.visualCursorDisplay).toBe("block")
  expect(diagnostics.cursorLeft).not.toBeNull()
  expect(diagnostics.cursorTop).not.toBeNull()
  expect(diagnostics.cursorRight).not.toBeNull()
  expect(diagnostics.cursorBottom).not.toBeNull()
  expect(diagnostics.cursorLeft).toBeGreaterThanOrEqual(0)
  expect(diagnostics.cursorTop).toBeGreaterThanOrEqual(0)
  expect(diagnostics.cursorRight).toBeLessThanOrEqual(diagnostics.viewportWidth)
  expect(diagnostics.cursorBottom).toBeLessThanOrEqual(diagnostics.viewportHeight)
  expect(diagnostics.cursorLeft).toBeGreaterThanOrEqual(diagnostics.previewProseLeft - 24)
  expect(diagnostics.cursorRight).toBeLessThanOrEqual(diagnostics.previewProseRight + 24)
  expect(diagnostics.cursorTop).toBeGreaterThanOrEqual(diagnostics.previewProseTop - 24)
  expect(diagnostics.cursorBottom).toBeLessThanOrEqual(diagnostics.previewProseBottom + 24)
})
