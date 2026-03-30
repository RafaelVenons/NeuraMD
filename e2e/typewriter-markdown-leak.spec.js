const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test("typewriter hides the preview overlay contract and keeps markdown editable in the native editor", async ({ page }) => {
  const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
  const scenario = runRailsScript("script/e2e/bootstrap_typewriter_markdown_leak.rb", { E2E_TOKEN: token })

  await signIn(page, scenario.credentials)
  await page.goto(scenario.note_path, { waitUntil: "domcontentloaded" })
  await expect(page.locator(".cm-editor")).toBeVisible()

  await page.locator(".cm-content").click()
  await page.keyboard.press("Control+\\")
  await expect(page.locator("body")).toHaveClass(/typewriter-mode/)
  await page.keyboard.press("Control+End")

  const diagnostics = await page.evaluate(() => {
    const previewPane = document.getElementById("preview-pane")
    const editorPane = document.getElementById("editor-pane")
    const firstEditorLine = document.querySelector(".cm-line")
    const codemirrorHost = document.getElementById("codemirror-host")
    const editorRect = codemirrorHost?.getBoundingClientRect()
    const lineRect = firstEditorLine?.getBoundingClientRect()

    return {
      previewDisplay: previewPane ? getComputedStyle(previewPane).display : null,
      editorPaneFlex: editorPane ? getComputedStyle(editorPane).flex : null,
      editorText: document.querySelector(".cm-content")?.innerText || null,
      editorHostWidth: editorRect?.width || null,
      firstLineLeft: lineRect?.left || null,
      hostLeft: editorRect?.left || null
    }
  })

  console.log(JSON.stringify(diagnostics, null, 2))

  expect(diagnostics.previewDisplay).toBe("none")
  expect(diagnostics.editorPaneFlex).toContain("1 1")
  expect(diagnostics.editorText).toContain("## Titulo principal")
  expect(diagnostics.editorText).toContain("[[Destino|")
  expect(diagnostics.editorText).toContain("```ruby")
  expect(diagnostics.editorHostWidth).toBeGreaterThan(0)
  expect(Math.abs(diagnostics.firstLineLeft - diagnostics.hostLeft)).toBeLessThan(40)
})
