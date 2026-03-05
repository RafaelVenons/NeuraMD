import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    debounceMs: { type: Number, default: 3000 },       // 3 segundos
    forceIntervalMs: { type: Number, default: 30000 }  // 30 segundos
  }

  connect() {
    this._timer = null
    this._forceTimer = null
    this._lastSavedContent = null
    this._pendingContent = null
    this._saving = false

    // Store bound handlers so we can remove them in disconnect()
    this._onEditorChange = this._handleEditorChange.bind(this)
    this._onBeforeUnload = this._handleBeforeUnload.bind(this)

    this.element.addEventListener("codemirror:change", this._onEditorChange)
    window.addEventListener("beforeunload", this._onBeforeUnload)

    this._startForceTimer()
  }

  disconnect() {
    clearTimeout(this._timer)
    clearInterval(this._forceTimer)
    this.element.removeEventListener("codemirror:change", this._onEditorChange)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
  }

  scheduleAutosave(content) {
    clearTimeout(this._timer)
    this._pendingContent = content
    this._setStatus("pendente")
    this._timer = setTimeout(() => this._save(content), this.debounceMsValue)
  }

  forceSave() {
    if (this._pendingContent) {
      clearTimeout(this._timer)
      this._save(this._pendingContent)
    }
  }

  // ── Private ─────────────────────────────────────────────

  _handleEditorChange(event) {
    this.scheduleAutosave(event.detail.value)
  }

  _handleBeforeUnload() {
    // Use sendBeacon for a fire-and-forget save on page unload
    if (!this._pendingContent || this._pendingContent === this._lastSavedContent) return
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const payload = JSON.stringify({ content_markdown: this._pendingContent })
    navigator.sendBeacon(
      this.urlValue,
      new Blob([payload], { type: "application/json" })
    )
  }

  async _save(content) {
    if (!content || content === this._lastSavedContent) return
    if (this._saving) return

    this._saving = true
    this._setStatus("salvando")

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ content_markdown: content })
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      this._lastSavedContent = content
      this._pendingContent = null
      this._setStatus("salvo")
    } catch (err) {
      console.error("Autosave error:", err)
      this._setStatus("erro")
    } finally {
      this._saving = false
    }
  }

  _startForceTimer() {
    this._forceTimer = setInterval(() => this.forceSave(), this.forceIntervalMsValue)
  }

  _setStatus(state) {
    this.dispatch("statuschange", {
      detail: { state },
      bubbles: true
    })
  }
}
