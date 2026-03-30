import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor"]

  connect() {
    this._enabled = localStorage.getItem("neuramd:typewriter") === "true"
    this._visualCursor = this._createVisualCursor()
    this._selectionChangeHandler = () => this._syncVisualCursor()
    this.element.addEventListener("codemirror:selectionchange", this._selectionChangeHandler)
    this._resizeHandler = () => this._syncVisualCursor()
    window.addEventListener("resize", this._resizeHandler)
    this._apply()
    setTimeout(() => this._syncCodemirror(), 0)
    setTimeout(() => {
      this._syncVisualCursor()
      this.dispatch("toggled", { detail: { enabled: this._enabled } })
    }, 0)
  }

  toggle() {
    this._enabled = !this._enabled
    localStorage.setItem("neuramd:typewriter", String(this._enabled))
    this._apply()
    this._syncCodemirror()
    setTimeout(() => this._syncVisualCursor(), 0)
    this.dispatch("toggled", { detail: { enabled: this._enabled } })
  }

  disconnect() {
    this.element.removeEventListener("codemirror:selectionchange", this._selectionChangeHandler)
    window.removeEventListener("resize", this._resizeHandler)
    this._visualCursor?.remove()
    this._visualCursor = null
  }

  _apply() {
    document.body.classList.toggle("typewriter-mode", this._enabled)
    const btn = document.querySelector("[data-editor-target='typewriterBtn']")
    btn?.classList.toggle("toolbar-btn--active", this._enabled)
    btn?.setAttribute("aria-pressed", String(this._enabled))
  }

  _syncCodemirror() {
    const controller = this._codemirrorController()
    controller?.setTypewriterMode(this._enabled)
  }

  _codemirrorController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "codemirror")
  }

  _createVisualCursor() {
    const cursor = document.createElement("div")
    cursor.className = "typewriter-visual-cursor"
    cursor.setAttribute("aria-hidden", "true")
    cursor.style.position = "fixed"
    cursor.style.display = "none"
    cursor.style.pointerEvents = "none"
    cursor.style.zIndex = "260"
    cursor.style.width = "4px"
    cursor.style.borderRadius = "999px"
    cursor.style.background = "color-mix(in srgb, var(--theme-accent-hover) 94%, white 6%)"
    cursor.style.boxShadow = "0 0 0 1px color-mix(in srgb, white 28%, transparent), 0 0 14px color-mix(in srgb, var(--theme-accent-hover) 68%, transparent), 0 0 24px color-mix(in srgb, var(--theme-accent-hover) 32%, transparent)"
    document.body.appendChild(cursor)
    return cursor
  }

  _syncVisualCursor() {
    if (!this._enabled || !this._visualCursor) {
      this._hideVisualCursor()
      return
    }

    const codemirror = this._codemirrorController()
    const cursorRect = codemirror?.getCursorClientRect()
    const editorAnchor = document.querySelector(".cm-line")
    const previewAnchor = document.querySelector("#preview-pane .preview-prose h1, #preview-pane .preview-prose h2, #preview-pane .preview-prose h3, #preview-pane .preview-prose h4, #preview-pane .preview-prose p, #preview-pane .preview-prose li, #preview-pane .preview-prose blockquote, #preview-pane .preview-prose pre")

    if (!cursorRect || !editorAnchor || !previewAnchor) {
      this._hideVisualCursor()
      return
    }

    const editorRect = editorAnchor.getBoundingClientRect()
    const previewRect = previewAnchor.getBoundingClientRect()
    const dx = previewRect.left - editorRect.left
    const dy = previewRect.top - editorRect.top
    const lineHeight = Math.max(18, cursorRect.bottom - cursorRect.top)

    this._visualCursor.style.display = "block"
    this._visualCursor.style.left = `${cursorRect.left + dx - 1}px`
    this._visualCursor.style.top = `${cursorRect.top + dy}px`
    this._visualCursor.style.height = `${lineHeight}px`
  }

  _hideVisualCursor() {
    if (!this._visualCursor) return
    this._visualCursor.style.display = "none"
  }
}
