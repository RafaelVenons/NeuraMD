import { Controller } from "@hotwired/stimulus"

// Orchestrates all sub-controllers: codemirror, preview, autosave, scroll-sync
export default class extends Controller {
  static targets = [
    "mainArea", "editorPane", "previewPane",
    "titleInput", "langBadge", "saveStatus",
    "previewToggleBtn", "typewriterBtn"
  ]
  static values = {
    autosaveUrl: String,
    slug: String,
    title: String,
    language: String
  }

  connect() {
    this._previewVisible = true
    this._scrollSyncLock = false
    this._scrollCooldown = null

    this._bindEditorEvents()
    this._bindKeyboardShortcuts()
    this._bindTitleInput()
    this._bindAutosaveStatus()
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
  }

  togglePreview() {
    this._previewVisible = !this._previewVisible
    const pane = this.previewPaneTarget

    if (this._previewVisible) {
      pane.classList.remove("hidden")
      this.previewToggleBtnTarget.classList.add("toolbar-btn--active")
    } else {
      pane.classList.add("hidden")
      this.previewToggleBtnTarget.classList.remove("toolbar-btn--active")
    }
  }

  // ── Editor events ─────────────────────────────────────────
  _bindEditorEvents() {
    // Listen for CodeMirror change events bubbling up
    this.element.addEventListener("codemirror:change", (e) => {
      const content = e.detail.value
      this._onContentChange(content)
    })

    // Listen for CodeMirror scroll events
    this.element.addEventListener("codemirror:scroll", (e) => {
      this._syncScrollEditorToPreview(e.detail.ratio)
    })

    // Listen for preview scroll events
    this.element.addEventListener("preview:scroll", (e) => {
      this._syncScrollPreviewToEditor(e.detail.ratio)
    })

    // Listen for autosave status changes
    this.element.addEventListener("autosave:statuschange", (e) => {
      this._onSaveStatus(e.detail)
    })
  }

  _onContentChange(content) {
    this._getPreviewController()?.update(content)
  }

  // The preview pane div itself has data-controller="preview" — use it directly
  _getPreviewController() {
    return this.application.getControllerForElementAndIdentifier(
      this.previewPaneTarget, "preview"
    )
  }

  // The editor pane has data-controller="codemirror ..." — use it directly
  _getCodemirrorController() {
    return this.application.getControllerForElementAndIdentifier(
      this.editorPaneTarget, "codemirror"
    )
  }

  // ── Scroll sync ──────────────────────────────────────────
  _syncScrollEditorToPreview(ratio) {
    if (this._scrollSyncLock) return
    this._scrollSyncLock = true
    this._getPreviewController()?.setScrollRatio(ratio)
    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._scrollSyncLock = false }, 400)
  }

  _syncScrollPreviewToEditor(ratio) {
    if (this._scrollSyncLock) return
    this._scrollSyncLock = true
    this._getCodemirrorController()?.setScrollRatio(ratio)
    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._scrollSyncLock = false }, 400)
  }

  // ── Keyboard shortcuts ───────────────────────────────────
  _bindKeyboardShortcuts() {
    this._keyHandler = (e) => {
      const ctrl = e.ctrlKey || e.metaKey

      if (ctrl && e.key === "p") {
        e.preventDefault()
        this.togglePreview()
      }
      if (ctrl && e.key === "f") {
        e.preventDefault()
        this._openDialog("find-replace-dialog")
      }
      if (ctrl && e.key === "g") {
        e.preventDefault()
        this._openDialog("jump-to-line-dialog")
      }
      if (e.key === "Escape") {
        this._closeAllDialogs()
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  }

  _openDialog(id) {
    document.getElementById(id)?.classList.remove("hidden")
    document.getElementById(id)?.querySelector("input")?.focus()
  }

  _closeAllDialogs() {
    document.getElementById("find-replace-dialog")?.classList.add("hidden")
    document.getElementById("jump-to-line-dialog")?.classList.add("hidden")
  }

  // ── Title input ──────────────────────────────────────────
  _bindTitleInput() {
    if (!this.hasTitleInputTarget) return

    let titleTimer = null
    this.titleInputTarget.addEventListener("input", (e) => {
      clearTimeout(titleTimer)
      titleTimer = setTimeout(() => this._saveTitle(e.target.value), 1000)
    })
  }

  async _saveTitle(title) {
    if (!title.trim()) return
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch(`/notes/${this.slugValue}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ note: { title } })
      })
    } catch (e) {
      console.error("Title save error:", e)
    }
  }

  // ── Save status ──────────────────────────────────────────
  _bindAutosaveStatus() {
    this.element.addEventListener("autosave:statuschange", (e) => {
      this._onSaveStatus(e.detail)
    })
  }

  _onSaveStatus({ state }) {
    if (!this.hasSaveStatusTarget) return
    const el = this.saveStatusTarget
    const map = {
      salvo: { text: "Salvo ✓", cls: "text-green-400" },
      salvando: { text: "Salvando...", cls: "text-yellow-400" },
      pendente: { text: "Pendente", cls: "text-gray-500" },
      erro: { text: "Erro ao salvar", cls: "text-red-400" }
    }
    const { text, cls } = map[state] || { text: "—", cls: "text-gray-500" }
    el.textContent = text
    el.className = `flex-shrink-0 text-xs ${cls}`
  }
}
