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
    draftMs:        { type: Number, default: 60000 },  // 60 seconds
    localMs:        { type: Number, default: 3000 }    // 3 seconds
  }

  static targets = ["saveButton", "status"]

  connect() {
    this._localTimer  = null
    this._draftTimer  = null
    this._lastDraftContent = this._loadLocal() || null
    this._pendingContent   = null
    this._saving = false

    this._onEditorChange  = this._handleEditorChange.bind(this)
    this._onBeforeUnload  = this._handleBeforeUnload.bind(this)

    this.element.addEventListener("codemirror:change", this._onEditorChange)
    window.addEventListener("beforeunload", this._onBeforeUnload)
  }

  disconnect() {
    clearTimeout(this._localTimer)
    clearTimeout(this._draftTimer)
    this.element.removeEventListener("codemirror:change", this._onEditorChange)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
  }

  // Called by the Save button
  async saveCheckpoint() {
    const content = this._pendingContent || this._loadLocal()
    if (!content) return
    await this._postSave(this.checkpointUrlValue, content, "checkpoint")
    this._clearLocal()
  }

  // ── Private ─────────────────────────────────────────────

  _handleEditorChange(event) {
    const content = event.detail.value
    this._pendingContent = content
    this._setStatus("pendente")

    // Layer 1: localStorage (3s debounce)
    clearTimeout(this._localTimer)
    this._localTimer = setTimeout(() => this._saveLocal(content), this.localMsValue)

    // Layer 2: server draft (60s debounce)
    clearTimeout(this._draftTimer)
    this._draftTimer = setTimeout(() => this._saveDraft(content), this.draftMsValue)
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
      try { localStorage.setItem(this.localKeyValue, content) } catch (_) {}
    }
  }

  _loadLocal() {
    if (!this.localKeyValue) return null
    try { return localStorage.getItem(this.localKeyValue) } catch (_) { return null }
  }

  _clearLocal() {
    if (this.localKeyValue) {
      try { localStorage.removeItem(this.localKeyValue) } catch (_) {}
    }
  }

  async _saveDraft(content) {
    if (content === this._lastDraftContent || this._saving) return
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
}
