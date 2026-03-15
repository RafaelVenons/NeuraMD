import { Controller } from "@hotwired/stimulus"

// Three-layer save strategy:
//   1. localStorage (3s debounce) — crash protection, zero requests
//   2. Server draft  (60s debounce) — POST /draft, upsert, no history
//   3. Checkpoint    (manual button) — POST /checkpoint, permanent, shown in history
export default class extends Controller {
  static values = {
    draftUrl:       String,
    checkpointUrl:  String,
    localKey:       String,
    serverUpdatedAt: String,
    draftMs:        { type: Number, default: 60000 },  // 60 seconds
    localMs:        { type: Number, default: 3000 }    // 3 seconds
  }

  static targets = ["saveButton", "status"]

  connect() {
    this._localTimer  = null
    this._draftTimer  = null
    this._lastDraftContent = null
    this._pendingContent   = null
    this._saving = false
    this._localSnapshot = this._loadLocalEntry()
    this._ignoreInitialServerEcho = false

    this._onEditorChange  = this._handleEditorChange.bind(this)
    this._onBeforeUnload  = this._handleBeforeUnload.bind(this)
    this._onEditorReady   = this._handleEditorReady.bind(this)

    this.element.addEventListener("codemirror:change", this._onEditorChange)
    this.element.addEventListener("codemirror:ready", this._onEditorReady)
    window.addEventListener("beforeunload", this._onBeforeUnload)
  }

  disconnect() {
    clearTimeout(this._localTimer)
    clearTimeout(this._draftTimer)
    this.element.removeEventListener("codemirror:change", this._onEditorChange)
    this.element.removeEventListener("codemirror:ready", this._onEditorReady)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
  }

  // Called by the Save button
  async saveCheckpoint() {
    const content = this._currentContent()
    if (!content) return
    await this._postSave(this.checkpointUrlValue, content, "checkpoint")
    this._clearLocal()
  }

  // Called before navigating away — saves pending content as draft immediately.
  async saveDraftNow({ force = true } = {}) {
    const content = this._currentContent()
    if (!content) return
    clearTimeout(this._draftTimer)
    await this._saveDraft(content, { force })
  }

  // ── Private ─────────────────────────────────────────────

  _handleEditorChange(event) {
    const content = event.detail.value

    if (this._ignoreInitialServerEcho && content === this._lastDraftContent) {
      this._ignoreInitialServerEcho = false
      return
    }

    this._ignoreInitialServerEcho = false
    this._pendingContent = content
    this._setStatus("pendente")

    // Layer 1: localStorage (3s debounce)
    clearTimeout(this._localTimer)
    this._localTimer = setTimeout(() => this._saveLocal(content), this.localMsValue)

    // Layer 2: server draft (60s debounce)
    clearTimeout(this._draftTimer)
    this._draftTimer = setTimeout(() => this._saveDraft(content), this.draftMsValue)
  }

  _handleEditorReady(event) {
    const editor = event.detail.editor
    const serverContent = editor.getValue()
    this._lastDraftContent = serverContent

    if (!this._shouldRestoreLocal(serverContent)) {
      this._ignoreInitialServerEcho = true
      return
    }

    const localContent = this._localSnapshot?.content || ""
    editor.setValue(localContent)
    this._pendingContent = localContent
    this._setStatus("pendente")
  }

  _handleBeforeUnload() {
    if (!this._pendingContent) return
    this._saveLocal(this._pendingContent)
    // Fire-and-forget draft on unload
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const payload   = JSON.stringify({ content_markdown: this._pendingContent })
    navigator.sendBeacon(this.draftUrlValue, new Blob([payload], { type: "application/json" }))
  }

  _saveLocal(content) {
    if (this.localKeyValue) {
      try {
        localStorage.setItem(this.localKeyValue, JSON.stringify({
          content,
          savedAt: Date.now()
        }))
      } catch (_) {}
    }
  }

  _loadLocalEntry() {
    if (!this.localKeyValue) return null
    try {
      const raw = localStorage.getItem(this.localKeyValue)
      if (!raw) return null

      try {
        const parsed = JSON.parse(raw)
        if (parsed && typeof parsed.content === "string") {
          return {
            content: parsed.content,
            savedAt: Number(parsed.savedAt) || 0,
            legacy: false
          }
        }
      } catch (_) {
        return { content: raw, savedAt: Number.MAX_SAFE_INTEGER, legacy: true }
      }

      return null
    } catch (_) {
      return null
    }
  }

  _currentContent() {
    return this._pendingContent || this._getCodemirrorController()?.getValue() || this._localSnapshot?.content || null
  }

  _getCodemirrorController() {
    const editorPane = this.element.querySelector("[data-controller~='codemirror']")
    if (!editorPane) return null

    return this.application.getControllerForElementAndIdentifier(editorPane, "codemirror")
  }

  _clearLocal() {
    if (this.localKeyValue) {
      try { localStorage.removeItem(this.localKeyValue) } catch (_) {}
    }
  }

  async _saveDraft(content, { force = false } = {}) {
    if ((content === this._lastDraftContent && !force) || this._saving) return
    await this._postSave(this.draftUrlValue, content, "draft")
    this._lastDraftContent = content
  }

  async _postSave(url, content, kind) {
    this._saving = true
    this._setStatus("salvando")
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ content_markdown: content })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      if (kind === "checkpoint") {
        this._pendingContent = null
        this._localSnapshot = null
      }
      this._setStatus(kind === "checkpoint" ? "salvo" : "rascunho")
    } catch (err) {
      console.error(`${kind} save error:`, err)
      this._setStatus("erro")
    } finally {
      this._saving = false
    }
  }

  _setStatus(state) {
    this.dispatch("statuschange", { detail: { state }, bubbles: true })
  }

  _shouldRestoreLocal(serverContent) {
    if (!this._localSnapshot?.content) return false

    const localContent = this._localSnapshot.content
    if (!localContent.trim()) return false
    if (localContent === serverContent) return false
    if (this._localSnapshot.legacy) return true

    const serverUpdatedAt = this.serverUpdatedAtValue ? Date.parse(this.serverUpdatedAtValue) : 0
    return this._localSnapshot.savedAt > serverUpdatedAt
  }
}
