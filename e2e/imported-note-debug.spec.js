const { test } = require("@playwright/test")
const { signIn } = require("./helpers/session")

test("debug imported note visibility", async ({ page }) => {
  const pageErrors = []
  const consoleErrors = []

  page.on("pageerror", (error) => {
    pageErrors.push(String(error))
  })

  page.on("console", (msg) => {
    if (msg.type() === "error") consoleErrors.push(msg.text())
  })

  await signIn(page, {
    email: "rafael.santos.garcia@hotmail.com",
    password: "password123"
  })

  await page.goto("/notes/picos", { waitUntil: "domcontentloaded" })

  const shellPayload = await page.evaluate(async () => {
    const response = await fetch("/notes/picos?shell=1", {
      headers: {
        Accept: "application/json",
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })

    const json = await response.json()
    return {
      ok: response.ok,
      revisionId: json.revision?.id || null,
      revisionKind: json.revision?.kind || null,
      revisionBytes: (json.revision?.content_markdown || "").length,
      title: json.note?.title || null
    }
  })

  const payload = await page.evaluate(() => {
    const host = document.querySelector("[data-controller~='codemirror']")
    const codemirror = window.Stimulus?.controllers?.find((item) => item.element === host && item.identifier === "codemirror")
    const content = document.querySelector("#codemirror-host .cm-content")
    const firstLine = content?.querySelector(".cm-line")
    const preview = document.querySelector(".preview-prose")
    const editorPane = document.getElementById("editor-pane")
    const debug = document.getElementById("note-debug")

    return {
      path: window.location.pathname,
      bodyClass: document.body.className,
      titleValue: document.querySelector("[data-editor-target='titleInput']")?.value || null,
      codemirrorValue: codemirror?.getValue?.() || null,
      codemirrorInitialValue: codemirror?.initialValueValue ?? null,
      editorPaneInitialValue: editorPane?.dataset?.codemirrorInitialValueValue ?? null,
      noteDebugBytes: debug?.dataset?.noteDebugBytes ?? null,
      noteDebugRevisionId: debug?.dataset?.noteDebugRevisionId ?? null,
      contentInnerText: content?.innerText || null,
      contentTextContent: content?.textContent || null,
      contentStyle: content ? {
        display: getComputedStyle(content).display,
        visibility: getComputedStyle(content).visibility,
        opacity: getComputedStyle(content).opacity,
        color: getComputedStyle(content).color
      } : null,
      firstLineText: firstLine?.textContent || null,
      firstLineStyle: firstLine ? {
        display: getComputedStyle(firstLine).display,
        visibility: getComputedStyle(firstLine).visibility,
        opacity: getComputedStyle(firstLine).opacity,
        color: getComputedStyle(firstLine).color
      } : null,
      previewText: preview?.innerText || null,
      previewStyle: preview ? {
        display: getComputedStyle(preview).display,
        visibility: getComputedStyle(preview).visibility,
        opacity: getComputedStyle(preview).opacity,
        color: getComputedStyle(preview).color
      } : null,
      localStorage: {
        typewriter: localStorage.getItem("neuramd:typewriter")
      },
      stimulusControllers: window.Stimulus?.controllers?.map((item) => item.identifier) || []
    }
  })

  console.log(JSON.stringify({ pageErrors, consoleErrors }, null, 2))
  console.log(JSON.stringify({ shellPayload }, null, 2))
  console.log(JSON.stringify(payload, null, 2))
})
