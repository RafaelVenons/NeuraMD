import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["root", "streamSource"]

  connect() {
    this._instanceId = `${Date.now()}-${Math.random().toString(16).slice(2)}`
    this.element.dataset.noteShellInstanceId = this._instanceId
    this._navigating = false
    this._pendingNavigation = null
    this._boundHandleNavigate = (event) => this._handleNavigateEvent(event)
    this._boundHandlePopstate = (event) => this._handlePopstate(event)
    document.addEventListener("note-shell:navigate", this._boundHandleNavigate)
    window.addEventListener("popstate", this._boundHandlePopstate)
    this._syncCurrentHistoryState()
  }

  disconnect() {
    document.removeEventListener("note-shell:navigate", this._boundHandleNavigate)
    window.removeEventListener("popstate", this._boundHandlePopstate)
  }

  async navigateTo(path, { pushHistory = true, force = false } = {}) {
    const normalizedPath = this._normalizeNotePath(path)
    if (!normalizedPath) return false
    if (this._navigating) {
      this._pendingNavigation = { path: normalizedPath, options: { pushHistory, force } }
      return false
    }
    if (!force && normalizedPath === window.location.pathname) return true

    this._navigating = true

    try {
      await this._saveDraftIfPossible()

      const response = await fetch(this._contextUrl(normalizedPath), {
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })
      const contentType = response.headers.get("content-type") || ""
      if (!contentType.includes("application/json")) throw new Error("Resposta inválida do shell.")

      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Falha ao carregar nota.")

      this._applyPayload(payload)
      const finalPath = payload.urls?.show || this._finalHistoryPath(response.url, normalizedPath)
      if (pushHistory) window.history.pushState(this._historyStateFor(finalPath), "", finalPath)
      else window.history.replaceState(this._historyStateFor(finalPath), "", finalPath)
      return true
    } catch (error) {
      console.error("Note shell navigation failed:", error)
      if (window.Turbo?.visit) window.Turbo.visit(normalizedPath)
      else window.location.assign(normalizedPath)
      return false
    } finally {
      this._navigating = false
      const pending = this._pendingNavigation
      this._pendingNavigation = null
      if (pending && pending.path !== normalizedPath) {
        await this.navigateTo(pending.path, pending.options)
      }
    }
  }

  async _handleNavigateEvent(event) {
    const path = event.detail?.path
    if (!path) return
    event.preventDefault?.()
    await this.navigateTo(path)
  }

  async _handlePopstate(event) {
    const path = event.state?.noteShellPath || this._normalizeNotePath(window.location.pathname)
    if (!path) return
    await this.navigateTo(path, { pushHistory: false, force: true })
  }

  async _saveDraftIfPossible() {
    const autosave = this.application.getControllerForElementAndIdentifier(this.element, "autosave")
    try {
      await autosave?.saveDraftNow?.()
    } catch (error) {
      console.warn("Note shell draft save failed before navigation:", error)
    }
  }

  _applyPayload(payload) {
    document.title = payload.title || document.title
    if (this.hasStreamSourceTarget) {
      this.streamSourceTarget.innerHTML = payload.html?.ai_requests_stream || ""
    }

    this._hydrateController("editor", payload)
    this._hydrateController("autosave", payload)
    this._hydrateController("ai-review", payload)
    this._hydrateController("wikilink", payload)
    this._hydrateController("tag-sidebar", payload)
    this._hydrateController("tts", payload)

    const embeddedGraph = this.element.querySelector("[data-controller~='graph']")
    const graph = embeddedGraph
      ? this.application.getControllerForElementAndIdentifier(embeddedGraph, "graph")
      : null
    graph?.focusNote?.(payload.note?.id)

    this.element.dispatchEvent(new CustomEvent("note-shell:changed", {
      detail: payload,
      bubbles: true
    }))
  }

  _hydrateController(identifier, payload) {
    let controller = this.application.getControllerForElementAndIdentifier(this.element, identifier)
    if (!controller) {
      const nestedElement = this.element.querySelector(`[data-controller~='${identifier}']`)
      if (nestedElement) controller = this.application.getControllerForElementAndIdentifier(nestedElement, identifier)
    }
    controller?.hydrateNoteContext?.(payload)
  }

  _normalizeNotePath(path) {
    if (!path) return null

    try {
      const url = new URL(path, window.location.origin)
      if (url.origin !== window.location.origin) return null
      if (!url.pathname.startsWith("/notes/")) return null
      return `${url.pathname}${url.search}${url.hash}`
    } catch (_) {
      return null
    }
  }

  _contextUrl(path) {
    const url = new URL(path, window.location.origin)
    url.searchParams.set("shell", "1")
    return `${url.pathname}${url.search}`
  }

  _finalHistoryPath(responseUrl, fallbackPath) {
    try {
      const url = new URL(responseUrl, window.location.origin)
      return `${url.pathname}${url.search}${url.hash}`
    } catch (_) {
      return fallbackPath
    }
  }

  _syncCurrentHistoryState() {
    const currentPath = this._normalizeNotePath(window.location.pathname)
    if (!currentPath) return

    window.history.replaceState(this._historyStateFor(currentPath), "", currentPath)
  }

  _historyStateFor(path) {
    return {
      ...(window.history.state || {}),
      noteShellPath: path
    }
  }
}
