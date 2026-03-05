import { Controller } from "@hotwired/stimulus"

// Wiki-link autocomplete and broken-link decoration for the CodeMirror editor.
//
// Triggered when the user types [[ inside the editor. Shows a dropdown of note
// suggestions filtered by title. Navigated with ↑/↓, confirmed with Enter/Tab,
// dismissed with Esc.
//
// After insertion, broken-link detection runs on every change event and adds
// the data-broken attribute to all [[...|uuid]] spans whose UUID returns 404.
export default class extends Controller {
  static values = {
    searchUrl: String
  }

  static targets = ["dropdown", "input"]

  connect() {
    this._suggestions  = []
    this._activeIndex  = -1
    this._searchTerm   = ""
    this._insertStart  = null  // CodeMirror position where [[ was typed
    this._debounceTimer = null
    this._brokenCache  = {}    // uuid → boolean (true = broken)

    this._onEditorChange  = this._handleEditorChange.bind(this)
    this._onEditorKeydown = this._handleEditorKeydown.bind(this)

    this.element.addEventListener("codemirror:change",  this._onEditorChange)
    this.element.addEventListener("codemirror:keydown", this._onEditorKeydown)
  }

  disconnect() {
    this.element.removeEventListener("codemirror:change",  this._onEditorChange)
    this.element.removeEventListener("codemirror:keydown", this._onEditorKeydown)
    this._closeDropdown()
  }

  // ── Editor event handlers ────────────────────────────────

  _handleEditorChange(event) {
    const { value, cursorPos, cm } = event.detail
    this._cm = cm

    // Detect [[ trigger
    const lineUpToCursor = this._lineUpToCursor(value, cursorPos)
    const triggerMatch   = lineUpToCursor.match(/\[\[([^\]|]*)$/)

    if (triggerMatch) {
      this._searchTerm  = triggerMatch[1]
      this._insertStart = cursorPos - triggerMatch[0].length
      this._scheduleSearch(this._searchTerm)
    } else {
      this._closeDropdown()
    }
  }

  _handleEditorKeydown(event) {
    if (!this._isDropdownOpen()) return
    const key = event.detail.key

    if (key === "ArrowDown") {
      event.detail.preventDefault?.()
      this._activeIndex = Math.min(this._activeIndex + 1, this._suggestions.length - 1)
      this._renderDropdown()
    } else if (key === "ArrowUp") {
      event.detail.preventDefault?.()
      this._activeIndex = Math.max(this._activeIndex - 1, 0)
      this._renderDropdown()
    } else if (key === "Enter" || key === "Tab") {
      if (this._activeIndex >= 0) {
        event.detail.preventDefault?.()
        this._insertSuggestion(this._suggestions[this._activeIndex])
      }
    } else if (key === "Escape") {
      this._closeDropdown()
    }
  }

  // ── Suggestion fetching ──────────────────────────────────

  _scheduleSearch(query) {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this._fetchSuggestions(query), 150)
  }

  async _fetchSuggestions(query) {
    try {
      const url      = `${this.searchUrlValue}?q=${encodeURIComponent(query)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      this._suggestions = await response.json()
      this._activeIndex = this._suggestions.length > 0 ? 0 : -1
      this._renderDropdown()
    } catch (_) {
      this._closeDropdown()
    }
  }

  // ── Insertion ────────────────────────────────────────────

  _insertSuggestion(note) {
    if (!this._cm || !note) return
    const markup = `[[${note.title}|${note.id}]]`
    this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
      detail: { markup, insertStart: this._insertStart },
      bubbles: true
    }))
    this._closeDropdown()
  }

  // ── Dropdown rendering ───────────────────────────────────

  _renderDropdown() {
    const dropdown = this.dropdownTarget
    if (this._suggestions.length === 0) {
      this._closeDropdown()
      return
    }

    dropdown.innerHTML = this._suggestions.map((note, i) => `
      <button
        class="wikilink-suggestion ${i === this._activeIndex ? "active" : ""}"
        data-index="${i}"
        type="button"
      >${this._escapeHtml(note.title)}</button>
    `).join("")

    dropdown.querySelectorAll("button").forEach((btn, i) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._activeIndex = i
        this._insertSuggestion(this._suggestions[i])
      })
    })

    dropdown.hidden = false
  }

  _isDropdownOpen() {
    return this.hasDropdownTarget && !this.dropdownTarget.hidden
  }

  _closeDropdown() {
    if (this.hasDropdownTarget) this.dropdownTarget.hidden = true
    this._suggestions = []
    this._activeIndex = -1
  }

  // ── Helpers ──────────────────────────────────────────────

  _lineUpToCursor(fullText, cursorPos) {
    const lineStart = fullText.lastIndexOf("\n", cursorPos - 1) + 1
    return fullText.slice(lineStart, cursorPos)
  }

  _escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
