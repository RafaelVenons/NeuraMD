const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")
const { signIn } = require("./helpers/session")

test("typewriter suppresses raw markdown leakage and keeps the preview layer active", async ({ page }) => {
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
    const firstEditorLine = document.querySelector(".cm-line")
    const previewHeading = document.querySelector(".preview-prose h2, .preview-prose h1")
    const previewLink = document.querySelector(".preview-prose a.wikilink")
    const codeBlock = document.querySelector(".preview-prose pre code")

    return {
      previewDisplay: previewPane ? getComputedStyle(previewPane).display : null,
      previewPosition: previewPane ? getComputedStyle(previewPane).position : null,
      editorLineVisibility: firstEditorLine
        ? getComputedStyle(firstEditorLine).visibility
        : null,
      previewHeadingText: previewHeading?.textContent?.trim() || null,
      previewLinkText: previewLink?.textContent?.trim() || null,
      previewCodeText: codeBlock?.textContent?.trim() || null
    }
  })

  console.log(JSON.stringify(diagnostics, null, 2))

  expect(diagnostics.previewDisplay).toBe("flex")
  expect(diagnostics.previewPosition).toBe("absolute")
  expect(diagnostics.editorLineVisibility).toBe("hidden")
  expect(diagnostics.previewHeadingText).toBe("Titulo principal")
  expect(diagnostics.previewLinkText).toBe("Destino")
  expect(diagnostics.previewCodeText).toContain("puts '**nao formatar**'")
})
