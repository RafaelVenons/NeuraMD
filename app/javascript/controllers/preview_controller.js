import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension } from "lib/marked_extensions"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    marked.use({ extensions: [emojiExtension, superscriptExtension, subscriptExtension, highlightExtension] })
    marked.setOptions({ gfm: true, breaks: false })

    this._debounceTimer = null
    this._scrollSyncEnabled = true
    this._isScrolling = false
    this._scrollCooldown = null
  }

  disconnect() {
    clearTimeout(this._debounceTimer)
  }

  // Called by editor when content changes
  update(content) {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this._render(content), 150)
  }

  // Set scroll position from ratio (0-1)
  setScrollRatio(ratio) {
    if (this._isScrolling) return
    const el = this.element
    const max = el.scrollHeight - el.clientHeight
    if (max > 0) el.scrollTop = max * ratio
  }

  getScrollRatio() {
    const el = this.element
    const max = el.scrollHeight - el.clientHeight
    return max > 0 ? el.scrollTop / max : 0
  }

  // Handle preview scroll → sync back to editor
  scroll() {
    if (this._isScrolling) return
    this._isScrolling = true

    this.dispatch("scroll", {
      detail: { ratio: this.getScrollRatio() },
      bubbles: true
    })

    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._isScrolling = false }, 400)
  }

  _render(content) {
    try {
      const html = marked.parse(content || "")
      this.outputTarget.innerHTML = html
      // Syntax highlight code blocks if available
      this._highlightCode()
    } catch (e) {
      console.error("Preview render error:", e)
    }
  }

  _highlightCode() {
    // Basic code block styling — no external dep needed
    this.outputTarget.querySelectorAll("pre code").forEach(el => {
      el.classList.add("cm-code-block")
    })
  }
}
