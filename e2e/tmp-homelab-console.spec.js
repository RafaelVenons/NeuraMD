const { test, expect } = require("@playwright/test")
const { signIn } = require("./helpers/session")

test("captures console errors and visible editor state on HomeLab note page", async ({ page }) => {
  const errors = []
  const failedRequests = []

  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text())
  })

  page.on("pageerror", (error) => {
    errors.push(`PAGEERROR: ${error.message}`)
  })

  page.on("requestfailed", (request) => {
    failedRequests.push({
      url: request.url(),
      method: request.method(),
      failure: request.failure()?.errorText || "unknown"
    })
  })

  await signIn(page, {
    email: "rafael.santos.garcia@hotmail.com",
    password: "password123"
  })

  const response = await page.goto("/notes/1-objetivo", { waitUntil: "domcontentloaded" })
  expect(response).not.toBeNull()

  await page.waitForTimeout(2000)

  const diagnostics = await page.evaluate(() => {
    const debug = document.getElementById("note-debug")
    const content = document.querySelector("#codemirror-host .cm-content")
    const lines = Array.from(document.querySelectorAll("#codemirror-host .cm-line")).slice(0, 5)
    const preview = document.querySelector(".preview-prose")

    return {
      location: window.location.pathname,
      title: document.title,
      debug: debug ? {
        slug: debug.dataset.noteDebugSlug,
        title: debug.dataset.noteDebugTitle,
        revisionId: debug.dataset.noteDebugRevisionId,
        revisionKind: debug.dataset.noteDebugRevisionKind,
        bytes: debug.dataset.noteDebugBytes
      } : null,
      bodyClasses: document.body.className,
      contentText: content?.innerText || null,
      contentStyle: content ? {
        display: getComputedStyle(content).display,
        visibility: getComputedStyle(content).visibility,
        opacity: getComputedStyle(content).opacity,
        color: getComputedStyle(content).color
      } : null,
      firstLines: lines.map((line) => ({
        text: line.textContent,
        display: getComputedStyle(line).display,
        visibility: getComputedStyle(line).visibility,
        opacity: getComputedStyle(line).opacity,
        color: getComputedStyle(line).color
      })),
      previewText: preview?.innerText || null
    }
  })

  console.log(JSON.stringify({ errors, failedRequests, diagnostics }, null, 2))
})
