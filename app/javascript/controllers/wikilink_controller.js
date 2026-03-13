import { Controller } from "@hotwired/stimulus"

// Wiki-link autocomplete for the CodeMirror editor.
//
// Typing [[  opens a dropdown. Left/Right cycles the hier_role that will be
// applied on insertion. Enter/Tab confirms, Esc dismisses.
//
// After every cursor move, detects if the cursor sits inside a completed
// [[Display|uuid]] and dispatches wikilink:cursor so tag_sidebar_controller
// can react (link-focus mode vs global mode).
export default class extends Controller {
  static values = { searchUrl: String }
  static targets = ["dropdown"]

  // Cycle order for hier_role; null = plain reference
  static ROLES      = [null, "f", "c", "b"]
  static ROLE_LABEL = { f: "Father", c: "Child", b: "Brother", null: "Ref" }
  // Full wiki-link pattern (completed, not mid-typing)
  static FULL_RE    = /\[\[([^\]|]+)\|([fcb]:)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]\]/gi

  connect() {
    this._suggestions  = []
    this._activeIndex  = -1
    this._insertStart  = null
    this._debounceTimer = null
    this._cm = null
    this._currentRole  = null   // null | 'f' | 'c' | 'b'
    this._lastFocusedUUID = null

    this._onEditorChange = this._handleEditorChange.bind(this)
    this.element.addEventListener("codemirror:change", this._onEditorChange)

    // Cursor movement without text change: re-run link detection only
    this._onSelectionChange = (e) => {
      const { value, cursorPos } = e.detail
      if (value !== undefined && cursorPos !== undefined) {
        this._detectCursorInLink(value, cursorPos)
      }
    }
    this.element.addEventListener("codemirror:selectionchange", this._onSelectionChange)

    // Cache the codemirror controller when it announces ready (needed for
    // cursor coordinates in _positionDropdown and focus in _closeDropdown).
    this._onCmReady = (e) => { this._cm = e.detail.editor }
    this.element.addEventListener("codemirror:ready", this._onCmReady)

    // Keyboard navigation for the dropdown.
    // Use capture phase so our handler fires BEFORE CodeMirror's keymap,
    // allowing us to call stopPropagation() when we consume a key.
    this._keydownHandler = (e) => {
      if (!this._isDropdownOpen()) return
      const handled = this._handleKey(e.key)
      if (handled) {
        e.preventDefault()
        e.stopPropagation()
      }
    }
    this.element.addEventListener("keydown", this._keydownHandler, { capture: true })
  }

  disconnect() {
    this.element.removeEventListener("codemirror:change", this._onEditorChange)
    this.element.removeEventListener("codemirror:selectionchange", this._onSelectionChange)
    this.element.removeEventListener("codemirror:ready", this._onCmReady)
    this.element.removeEventListener("keydown", this._keydownHandler, { capture: true })
    this._closeDropdown()
  }

  // ── Editor change handler ────────────────────────────────

  _handleEditorChange(event) {
    const { value, cursorPos, cm } = event.detail
    if (cm) this._cm = cm

    // Detect mid-typing trigger [[ ... (dropdown autocomplete)
    const lineUpToCursor = this._lineUpToCursor(value, cursorPos)
    const triggerMatch   = lineUpToCursor.match(/\[\[([^\]|]*)$/)

    if (triggerMatch) {
      this._searchTerm  = triggerMatch[1]
      this._insertStart = cursorPos - triggerMatch[0].length
      this._scheduleSearch(this._searchTerm)
    } else {
      this._closeDropdown()
    }

    // Detect cursor inside a completed [[Display|uuid]] and dispatch event
    this._detectCursorInLink(value, cursorPos)
  }

  _detectCursorInLink(value, cursorPos) {
    const re = new RegExp(this.constructor.FULL_RE.source, "gi")
    let match
    let focused = null
    while ((match = re.exec(value)) !== null) {
      const from = match.index
      const to   = from + match[0].length
      if (cursorPos >= from && cursorPos <= to) {
        focused = {
          display: match[1],
          role: match[2] ? match[2].replace(":", "") : null,
          uuid: match[3],
          from,
          to
        }
        break
      }
    }

    const uuid = focused?.uuid ?? null
    if (uuid !== this._lastFocusedUUID) {
      this._lastFocusedUUID = uuid
      this.element.dispatchEvent(new CustomEvent("wikilink:cursor", {
        detail: { link: focused },
        bubbles: true
      }))
    }
  }

  // ── Key interceptor (called by codemirror_controller via Prec.highest) ──

  // Returns true to consume the key (blocking CodeMirror defaults),
  // false to let it pass through normally.
  _handleKey(key) {
    if (!this._isDropdownOpen()) return false

    switch (key) {
      case "ArrowDown":
        this._activeIndex = Math.min(this._activeIndex + 1, this._suggestions.length - 1)
        this._renderDropdown()
        return true

      case "ArrowUp":
        this._activeIndex = Math.max(this._activeIndex - 1, 0)
        this._renderDropdown()
        return true

      case "ArrowRight":
        this._cycleRole(1)
        return true

      case "ArrowLeft":
        this._cycleRole(-1)
        return true

      case "Enter":
      case "Tab":
        if (this._activeIndex >= 0) {
          this._insertSuggestion(this._suggestions[this._activeIndex])
        }
        return true

      case "Escape":
        this._closeDropdown()
        return true

      default:
        return false
    }
  }

  _cycleRole(dir) {
    const roles = this.constructor.ROLES
    const i = roles.indexOf(this._currentRole)
    this._currentRole = roles[((i + dir) + roles.length) % roles.length]
    this._renderDropdown()
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
    if (!note) return
    const rolePrefix = this._currentRole ? `${this._currentRole}:` : ""
    const markup = `[[${note.title}|${rolePrefix}${note.id}]]`
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

    const roleKey   = this._currentRole ?? "null"
    const roleLabel = this.constructor.ROLE_LABEL[roleKey]
    const roleClass = `wikilink-role-${roleKey}`

    dropdown.innerHTML = `
      <div class="wikilink-role-bar">
        <span class="wikilink-role-hint">← →</span>
        <span class="wikilink-role-current ${roleClass}">${roleLabel}</span>
      </div>
      ${this._suggestions.map((note, i) => `
        <button
          class="wikilink-suggestion ${i === this._activeIndex ? "active" : ""}"
          data-index="${i}"
          type="button"
        >${this._escapeHtml(note.title)}</button>
      `).join("")}
    `

    dropdown.querySelectorAll("button").forEach((btn, i) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._activeIndex = i
        this._insertSuggestion(this._suggestions[i])
      })
    })

    this._positionDropdown()
    dropdown.hidden = false
  }

  // ── Positioning ──────────────────────────────────────────

  _positionDropdown() {
    if (!this._cm?.view || this._insertStart == null) return
    const coords = this._cm.view.coordsAtPos(this._insertStart)
    if (!coords) return

    const dropdown = this.dropdownTarget
    const paneRect = this.element.getBoundingClientRect()
    const spaceBelow = window.innerHeight - coords.bottom

    if (spaceBelow >= 80) {
      dropdown.style.top    = `${coords.bottom - paneRect.top + 4}px`
      dropdown.style.bottom = "auto"
    } else {
      dropdown.style.top    = "auto"
      dropdown.style.bottom = `${paneRect.bottom - coords.top + 4}px`
    }

    const left    = coords.left - paneRect.left
    const maxLeft = paneRect.width - 240 - 8
    dropdown.style.left = `${Math.max(4, Math.min(left, maxLeft))}px`
  }

  // ── State ────────────────────────────────────────────────

  _isDropdownOpen() {
    return this.hasDropdownTarget && !this.dropdownTarget.hidden
  }

  _closeDropdown() {
    if (this.hasDropdownTarget) this.dropdownTarget.hidden = true
    this._suggestions   = []
    this._activeIndex   = -1
    this._currentRole   = null
    this._cm?.focus()
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
