const { test, expect } = require("@playwright/test")
const { execFileSync } = require("node:child_process")
const path = require("node:path")
const { signIn } = require("./helpers/session")

function loadScenario() {
  const cwd = path.resolve(__dirname, "..")
  const ruby = `
    def pick_note(tag_name)
      note = Note.joins(:tags)
        .where(tags: { name: tag_name })
        .where.not(head_revision_id: nil)
        .order(updated_at: :desc)
        .distinct
        .first

      raise "No readable note for tag #{tag_name}" unless note

      {
        tag: tag_name,
        slug: note.slug,
        title: note.title,
        first_line: note.head_revision&.content_markdown.to_s.lines.first.to_s.strip
      }
    end

    payload = {
      credentials: {
        email: "rafael.santos.garcia@hotmail.com",
        password: "password123"
      },
      notes: [
        pick_note("new-specs"),
        pick_note("queue")
      ]
    }

    puts payload.to_json
  `

  return JSON.parse(execFileSync("bin/rails", ["runner", ruby], {
    cwd,
    env: {
      ...process.env,
      RAILS_ENV: "development"
    },
    encoding: "utf8"
  }).trim())
}

async function visibleEditorText(page) {
  return page.evaluate(() => {
    const content = document.querySelector("#codemirror-host .cm-content")
    if (!content) return null

    return Array.from(content.querySelectorAll(".cm-line"))
      .filter((line) => {
        const style = window.getComputedStyle(line)
        return style.display !== "none" &&
          style.visibility !== "hidden" &&
          style.opacity !== "0" &&
          style.color !== "rgba(0, 0, 0, 0)"
      })
      .map((line) => line.textContent)
      .join("\n")
  })
}

test("shows imported content from new-specs and queue in editor and preview", async ({ page }) => {
  const scenario = loadScenario()

  await signIn(page, scenario.credentials)

  for (const note of scenario.notes) {
    const normalizedHeading = (note.first_line || "").replace(/^#+\s*/, "")
    const response = await page.goto(`/notes/${note.slug}`, { waitUntil: "domcontentloaded" })

    expect(response).not.toBeNull()
    expect(response.ok()).toBeTruthy()

    await expect(page.locator("[data-editor-target='titleInput']")).toHaveValue(note.title)
    await expect(page.locator(".cm-editor")).toBeVisible()
    await expect(page.locator(".preview-prose")).toBeVisible()

    const editorText = await visibleEditorText(page)
    expect(editorText).toBeTruthy()
    expect(editorText).toContain(note.first_line)

    await expect(page.locator(".preview-prose")).toContainText(normalizedHeading)
    await expect(page.locator("body")).not.toContainText("We're sorry, but something went wrong.")
  }
})
