const { test, expect } = require("@playwright/test")
const { runRailsScript } = require("./helpers/rails")

async function signIn(page, credentials) {
  await page.goto("/users/sign_in")
  await page.getByLabel("E-mail").fill(credentials.email)
  await page.getByLabel("Senha").fill(credentials.password)
  await page.getByRole("button", { name: "Entrar" }).click()
  await expect(page).toHaveURL(/\/graph/)
}

async function forceFallbackPolling(page) {
  await page.evaluate(() => {
    const host = document.querySelector("[data-controller~='ai-review']")
    const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "ai-review")
    controller._setTransportState(false)
  })
}

async function refreshQueue(page) {
  await page.evaluate(() => {
    const host = document.querySelector("[data-controller~='ai-review']")
    const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "ai-review")
    controller.refreshQueue()
  })
}

async function enqueuePromise(page, title, prefix = "") {
  await page.locator(".cm-content").click()
  await page.keyboard.type(`${prefix}[[${title}]]`)
  await expect(page.locator(".wikilink-dropdown:not([hidden])")).toBeVisible()
  const responsePromise = page.waitForResponse((response) =>
    response.request().method() === "POST" &&
    response.url().includes("/create_from_promise") &&
    response.request().postData()?.includes(`"title":"${title}"`) &&
    response.status() === 201
  )
  await page.getByRole("button", { name: "Gerar com IA" }).click()
  const response = await responsePromise
  const payload = await response.json()
  expect(payload.request_id).toBeTruthy()
  const card = queueCard(page, title)
  await expect(card).toBeVisible()
  return payload.request_id
}

function queueCard(page, title) {
  return page.locator("[data-ai-review-target='queueDock'] [data-request-id]").filter({ hasText: title }).first()
}

async function expectCard(page, title, status, label) {
  const card = queueCard(page, title)
  await expect(card).toBeVisible()
  await expect(card).toHaveAttribute("data-queue-status", status)
  await expect(card).toContainText(label)
  await expect(card).toContainText(title)
}

async function expectSeedNoteReviewWorkspace(page, title, bodyText) {
  await expect(page.getByRole("button", { name: "Aplicar" })).toBeVisible()
  await expect(page.getByRole("button", { name: "Recusar" })).toBeVisible()
  await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText("Nota criada com IA")
  await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText(title)
  await expect(page.locator("[data-ai-review-target='proposalDiff']")).toContainText(bodyText)
}

async function transitionRequest(request, id, transition, body) {
  const response = await request.post(`/test_support/ai_requests/${id}/transition`, {
    data: body ? { transition, body } : { transition }
  })
  expect(response.ok()).toBeTruthy()
  return await response.json()
}

test.describe("AI queue promise sequencing", () => {
  test("keeps the second promise queued until the first one finishes and updates the queue through the whole flow", async ({ page, request }) => {
    const token = `${Date.now()}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_queue_sequence.rb", { E2E_TOKEN: token })
    const [firstPromiseTitle, secondPromiseTitle] = scenario.promise_titles

    await signIn(page, scenario.credentials)
    await page.goto(scenario.note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await forceFallbackPolling(page)

    const firstRequestId = await enqueuePromise(page, firstPromiseTitle)
    const secondRequestId = await enqueuePromise(page, secondPromiseTitle, "\n\n")
    const requestIds = [firstRequestId, secondRequestId]

    await refreshQueue(page)

    await expect(page.locator("[data-ai-review-target='queueDock']")).toBeVisible()
    await expectCard(page, firstPromiseTitle, "queued", "Criar")
    await expectCard(page, secondPromiseTitle, "queued", "Criar")

    await transitionRequest(request, firstRequestId, "running")
    await refreshQueue(page)
    await expectCard(page, firstPromiseTitle, "running", "Criando")
    await expectCard(page, secondPromiseTitle, "queued", "Criar")

    await transitionRequest(request, firstRequestId, "succeeded", `# ${firstPromiseTitle}\n\nConteudo da primeira promise.`)
    await refreshQueue(page)
    await expectCard(page, firstPromiseTitle, "succeeded", "Criado")
    await expectCard(page, secondPromiseTitle, "queued", "Criar")

    await transitionRequest(request, secondRequestId, "running")
    await refreshQueue(page)
    await expectCard(page, firstPromiseTitle, "succeeded", "Criado")
    await expectCard(page, secondPromiseTitle, "running", "Criando")

    await transitionRequest(request, secondRequestId, "succeeded", `# ${secondPromiseTitle}\n\nConteudo da segunda promise.`)
    await refreshQueue(page)
    await expectCard(page, firstPromiseTitle, "succeeded", "Criado")
    await expectCard(page, secondPromiseTitle, "succeeded", "Criado")
  })

  test("shows a succeeded promise in the queue, keeps it after reload, and opens human review before acceptance", async ({ page, request }) => {
    const token = `${Date.now()}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_queue_sequence.rb", { E2E_TOKEN: token })
    const [promiseTitle] = scenario.promise_titles
    const bodyText = "Conteudo aguardando revisao humana."

    await signIn(page, scenario.credentials)
    await page.goto(scenario.note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await forceFallbackPolling(page)

    const requestId = await enqueuePromise(page, promiseTitle)

    await transitionRequest(request, requestId, "running")
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "running", "Criando")

    await transitionRequest(request, requestId, "succeeded", `# ${promiseTitle}\n\n${bodyText}`)
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "succeeded", "Criado")

    await page.reload()
    await expect(page.locator(".cm-editor")).toBeVisible()
    await forceFallbackPolling(page)
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "succeeded", "Criado")

    await queueCard(page, promiseTitle).click()
    await expect(page).toHaveURL(new RegExp(`/notes/promessa-queue-a-${token}|/notes/promessa-queue-b-${token}`))
    await expectSeedNoteReviewWorkspace(page, promiseTitle, bodyText)
  })

  test("keeps queue and shell history for AI promise creation from an empty source note after reload", async ({ page, request }) => {
    const token = `${Date.now()}`
    const scenario = runRailsScript("script/e2e/bootstrap_ai_queue_sequence.rb", {
      E2E_TOKEN: token,
      BLANK_SOURCE: "1"
    })
    const [promiseTitle] = scenario.promise_titles
    const bodyText = "Conteudo gerado a partir do titulo."

    await signIn(page, scenario.credentials)
    await page.goto(scenario.note_path)
    await expect(page.locator(".cm-editor")).toBeVisible()

    await forceFallbackPolling(page)

    const requestId = await enqueuePromise(page, promiseTitle)
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "queued", "Criar")

    await transitionRequest(request, requestId, "running")
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "running", "Criando")

    await transitionRequest(request, requestId, "succeeded", `# ${promiseTitle}\n\n${bodyText}`)
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "succeeded", "Criado")

    await page.reload()
    await expect(page.locator(".cm-editor")).toBeVisible()
    await forceFallbackPolling(page)
    await refreshQueue(page)
    await expectCard(page, promiseTitle, "succeeded", "Criado")

    await page.getByRole("button", { name: "Histórico de IA" }).click()
    await page.getByRole("button", { name: "Shell" }).click()
    await expect(page.locator("[data-ai-review-target='historyList']")).toContainText(promiseTitle)
    await expect(page.locator("[data-ai-review-target='historyList']")).toContainText("Concluida")
  })
})
