import { Controller } from "@hotwired/stimulus"

// Wiki-link autocomplete for the CodeMirror editor.
//
// Typing [[  opens a dropdown. Left/Right cycles the hier_role that will be
// applied on insertion. Enter/Tab confirms, Esc dismisses.
//
// After every cursor move, detects if the cursor sits inside a completed
// [[Display|uuid]], [[Display|f:uuid]], [[Display|c:uuid]] or [[Display|b:uuid]]
// and dispatches wikilink:cursor so tag_sidebar_controller
// can react (link-focus mode vs global mode).
export default class extends Controller {
  static values = { searchUrl: String, createPromiseUrl: String, currentNoteId: String }
  static targets = ["dropdown"]

  // Cycle order for hier_role; null = plain reference
  static ROLES      = [null, "f", "c", "b"]
  static ROLE_LABEL = { f: "Father", c: "Child", b: "Brother", null: "Ref" }
  // Full wiki-link pattern (completed, not mid-typing)
  static FULL_RE    = /\[\[([^\]|]+)\|([a-z]+:)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]\]/gi

  connect() {
    this.element.dataset.wikilinkReady = "true"
    this._suggestions  = []
    this._activeIndex  = -1
    this._insertStart  = null
    this._debounceTimer = null
    this._cm = null
    this._currentRole  = null   // null | 'f' | 'c' | 'b'
    this._lastFocusedUUID = null
    this._focusedLink = null
    this._isComposing = false
    this._dropdownMode = "search"
    this._promiseTitle = null
    this._pendingPromiseCreations = new Set()

    this._onEditorChange = this._handleEditorChange.bind(this)
    this.element.addEventListener("codemirror:change", this._onEditorChange)

    // Cursor movement without text change: re-run link detection only
    this._onSelectionChange = (e) => {
      const { value, cursorPos, isComposing } = e.detail
      this._isComposing = !!isComposing
      if (value !== undefined && cursorPos !== undefined) {
        this._detectCursorInLink(value, cursorPos)
      }
    }
    this.element.addEventListener("codemirror:selectionchange", this._onSelectionChange)

    // Cache the codemirror controller when it announces ready (needed for
    // cursor coordinates in _positionDropdown and focus in _closeDropdown).
    this._onCmReady = (e) => { this._cm = e.detail.editor }
    this.element.addEventListener("codemirror:ready", this._onCmReady)

    this._onCompositionChange = (e) => {
      this._isComposing = !!e.detail.isComposing
      if (this._isComposing) this._closeDropdown({ preserveFocus: true })
    }
    this.element.addEventListener("codemirror:compositionchange", this._onCompositionChange)

    // Keyboard navigation for the dropdown.
    // Use capture phase so our handler fires BEFORE CodeMirror's keymap,
    // allowing us to call stopPropagation() when we consume a key.
    this._keydownHandler = (e) => {
      if (e.isComposing || e.keyCode === 229 || this._isComposing) return
      const handled = this._handleKey(e.key)
      if (handled) {
        e.preventDefault()
        e.stopPropagation()
      }
    }
    this.element.addEventListener("keydown", this._keydownHandler, { capture: true })
  }

  disconnect() {
    delete this.element.dataset.wikilinkReady
    this.element.removeEventListener("codemirror:change", this._onEditorChange)
    this.element.removeEventListener("codemirror:selectionchange", this._onSelectionChange)
    this.element.removeEventListener("codemirror:ready", this._onCmReady)
    this.element.removeEventListener("codemirror:compositionchange", this._onCompositionChange)
    this.element.removeEventListener("keydown", this._keydownHandler, { capture: true })
    this._closeDropdown()
  }

  hydrateNoteContext(payload) {
    const note = payload.note || {}
    const urls = payload.urls || {}

    this.createPromiseUrlValue = urls.wikilink_create_promise || this.createPromiseUrlValue
    this.currentNoteIdValue = note.id || this.currentNoteIdValue
    this._closeDropdown({ preserveFocus: true })
    this._lastFocusedUUID = null
  }

  // ── Editor change handler ────────────────────────────────

  _handleEditorChange(event) {
    const { value, cursorPos, cm, isComposing } = event.detail
    if (cm) this._cm = cm
    this._isComposing = !!isComposing

    if (this._isComposing) {
      this._closeDropdown({ preserveFocus: true })
      this._detectCursorInLink(value, cursorPos)
      return
    }

    const lineUpToCursor = this._lineUpToCursor(value, cursorPos)
    const promiseMatch = lineUpToCursor.match(/\[\[([^\]|]+)\]\]$/)

    if (promiseMatch) {
      clearTimeout(this._debounceTimer)
      this._promiseTitle = promiseMatch[1].trim()
      this._insertStart = cursorPos - promiseMatch[0].length
      this._showPromiseActions()
      this._detectCursorInLink(value, cursorPos)
      return
    }

    // Detect mid-typing trigger [[ ... (dropdown autocomplete)
    const triggerMatch   = lineUpToCursor.match(/\[\[([^\]|]*)$/)

    if (triggerMatch) {
      this._dropdownMode = "search"
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

    this._focusedLink = focused
    if (focused && this._isDropdownOpen()) {
      this._closeDropdown({ preserveFocus: true })
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
    if (this._focusedLink && (key === "ArrowDown" || key === "ArrowUp")) {
      return this._cycleFocusedLinkRole(key === "ArrowDown" ? 1 : -1)
    }

    if (this._isDropdownOpen()) {
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
            if (this._dropdownMode === "promise") this._selectPromiseAction(this._suggestions[this._activeIndex])
            else this._insertSuggestion(this._suggestions[this._activeIndex])
          }
          return true

        case "Escape":
          this._closeDropdown()
          return true

        case " ":
          if (this._dropdownMode === "promise") {
            this._closeDropdown({ preserveFocus: true })
          }
          return false

        default:
          return false
      }
    }

    switch (key) {
      case "ArrowDown":
        return this._cycleFocusedLinkRole(1)
      case "ArrowUp":
        return this._cycleFocusedLinkRole(-1)
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

  _cycleFocusedLinkRole(dir) {
    if (!this._focusedLink || !this._cm) return false

    const roles = this.constructor.ROLES
    const currentRole = this._focusedLink.role || null
    const index = roles.indexOf(currentRole)
    const nextRole = roles[((index + dir) + roles.length) % roles.length]
    const rolePrefix = nextRole ? `${nextRole}:` : ""
    const markup = `[[${this._focusedLink.display}|${rolePrefix}${this._focusedLink.uuid}]]`
    const cursorOffset = Math.max(0, (this._cm.getSelectionRange?.().from ?? this._focusedLink.to) - this._focusedLink.from)
    const nextCursor = Math.min(this._focusedLink.from + cursorOffset, this._focusedLink.from + markup.length - 2)

    this._cm.replaceRange(this._focusedLink.from, this._focusedLink.to, markup, {
      selectionAnchor: nextCursor
    })
    this._focusedLink = {
      ...this._focusedLink,
      role: nextRole,
      to: this._focusedLink.from + markup.length
    }
    return true
  }

  // ── Suggestion fetching ──────────────────────────────────

  _scheduleSearch(query) {
    clearTimeout(this._debounceTimer)
    this._showSearchLoading()
    this._debounceTimer = setTimeout(() => this._fetchSuggestions(query), 75)
  }

  async _fetchSuggestions(query) {
    try {
      if (this._dropdownMode !== "search") return
      const params = new URLSearchParams({ q: query })
      if (this.currentNoteIdValue) params.set("exclude_id", this.currentNoteIdValue)
      const url = `${this.searchUrlValue}?${params.toString()}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const suggestions = await response.json()
      if (this._dropdownMode !== "search" || this._searchTerm !== query) return
      this._suggestions = this._rankSuggestionsByCosineSimilarity(suggestions, query)
      this._activeIndex = this._suggestions.length > 0 ? 0 : -1
      this._renderDropdown()
    } catch (_) {
      this._closeDropdown()
    }
  }

  _showPromiseActions() {
    if (!this._promiseTitle) {
      this._closeDropdown({ preserveFocus: true })
      return
    }

    this._dropdownMode = "promise"
    this._suggestions = [
      { action: "blank", label: "Gerar nota em branco", description: "Cria a nota e substitui o wikilink pela versao com UUID." },
      { action: "ai", label: "Gerar com IA", description: "Cria a nota e pede um rascunho inicial ao provider configurado." },
      { action: "ignore", label: "Ignorar", description: "Mantem o wikilink sem UUID. Espaco fecha este menu." }
    ]
    this._activeIndex = 0
    this._renderDropdown()
  }

  _showSearchLoading() {
    this._dropdownMode = "search"
    this._suggestions = [
      {
        label: "Buscando notas...",
        description: "Continue digitando para filtrar os resultados.",
        loading: true
      }
    ]
    this._activeIndex = -1
    this._renderDropdown()
  }

  // ── Insertion ────────────────────────────────────────────

  _insertSuggestion(note) {
    if (!note || note.loading) return
    const rolePrefix = this._currentRole ? `${this._currentRole}:` : ""
    const markup = `[[${note.title}|${rolePrefix}${note.id}]]`
    this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
      detail: { markup, insertStart: this._insertStart },
      bubbles: true
    }))
    this._closeDropdown()
  }

  async _selectPromiseAction(option) {
    if (!option) return
    if (option.action === "ignore") {
      this._closeDropdown({ preserveFocus: true })
      return
    }

    const promiseKey = `${option.action}:${(this._promiseTitle || "").toLowerCase()}`
    if (this._pendingPromiseCreations.has(promiseKey)) {
      window.alert("Esta nota ja esta sendo criada.")
      return
    }

    this._pendingPromiseCreations.add(promiseKey)

    try {
      const response = await fetch(this.createPromiseUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify({
          title: this._promiseTitle,
          mode: option.action
        })
      })
      const data = await this._parseJsonResponse(response, "Falha ao criar nota.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao criar nota.")

      const rolePrefix = this._currentRole ? `${this._currentRole}:` : ""
      const markup = `[[${data.note_title}|${rolePrefix}${data.note_id}]]`
      this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
        detail: { markup, insertStart: this._insertStart },
        bubbles: true
      }))
      this._closeDropdown()

      if (option.action === "ai") {
        const editorRoot = this.element.closest("#editor-root")
        const aiReview = editorRoot
          ? this.application.getControllerForElementAndIdentifier(editorRoot, "ai-review")
          : null
        const promiseDetail = {
          requestId: data.request_id,
          requestStatus: data.request_status,
          noteId: data.note_id,
          noteSlug: data.note_slug,
          noteTitle: data.note_title
        }

        aiReview?.handlePromiseEnqueued?.(promiseDetail)
        this.element.dispatchEvent(new CustomEvent("promise:ai-enqueued", {
          detail: promiseDetail,
          bubbles: true
        }))
      }

      await this._autosaveController()?.saveDraftNow?.()

      if (option.action === "blank") {
        const shell = this.application.getControllerForElementAndIdentifier(this.element.closest("#editor-root"), "note-shell")
        if (shell?.navigateTo) await shell.navigateTo(data.note_url)
        else window.location.assign(data.note_url)
        return
      }
    } catch (error) {
      window.alert(error.message || "Falha ao criar nota.")
    } finally {
      this._pendingPromiseCreations.delete(promiseKey)
    }
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
        >
          <span>${this._escapeHtml(note.title || note.label)}</span>
          ${note.matched_alias ? `<span class="wikilink-alias-hint">aka: ${this._escapeHtml(note.matched_alias)}</span>` : ""}
          ${note.description ? `<span class="block mt-1 text-xs opacity-70">${this._escapeHtml(note.description)}</span>` : ""}
        </button>
      `).join("")}
    `

    dropdown.querySelectorAll("button").forEach((btn, i) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._activeIndex = i
        if (this._dropdownMode === "promise") this._selectPromiseAction(this._suggestions[i])
        else this._insertSuggestion(this._suggestions[i])
      })
    })

    this._positionDropdown()
    dropdown.hidden = false
    this._scrollActiveSuggestionIntoView()
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

  _scrollActiveSuggestionIntoView() {
    if (!this._isDropdownOpen()) return
    const activeSuggestion = this.dropdownTarget.querySelector(".wikilink-suggestion.active")
    if (!activeSuggestion) return

    activeSuggestion.scrollIntoView({ block: "nearest" })
  }

  // ── State ────────────────────────────────────────────────

  _isDropdownOpen() {
    return this.hasDropdownTarget && !this.dropdownTarget.hidden
  }

  _closeDropdown({ preserveFocus = false } = {}) {
    if (this.hasDropdownTarget) this.dropdownTarget.hidden = true
    this._suggestions   = []
    this._activeIndex   = -1
    this._currentRole   = null
    this._insertStart   = null
    this._promiseTitle  = null
    this._dropdownMode  = "search"
    if (!preserveFocus && !this._isComposing) this._cm?.focus()
  }

  // ── Helpers ──────────────────────────────────────────────

  _lineUpToCursor(fullText, cursorPos) {
    const lineStart = fullText.lastIndexOf("\n", cursorPos - 1) + 1
    return fullText.slice(lineStart, cursorPos)
  }

  _rankSuggestionsByCosineSimilarity(suggestions, query) {
    const normalizedQuery = this._normalizeSearchText(query)
    if (!normalizedQuery) return suggestions

    return [...suggestions]
      .map((note) => ({
        note,
        score: Math.max(
          this._suggestionSearchScore(note.title, normalizedQuery),
          note.matched_alias ? this._suggestionSearchScore(note.matched_alias, normalizedQuery) : 0
        )
      }))
      .filter(({ score }) => score > 0)
      .sort((left, right) => {
        if (right.score !== left.score) return right.score - left.score
        return left.note.title.localeCompare(right.note.title, "pt-BR")
      })
      .map(({ note }) => note)
  }

  _suggestionSearchScore(title, normalizedQuery) {
    const normalizedTitle = this._normalizeSearchText(title)
    if (!normalizedTitle) return 0
    if (normalizedTitle.includes(normalizedQuery)) return 1

    const titleVector = this._trigramVector(normalizedTitle)
    const queryVector = this._trigramVector(normalizedQuery)
    return this._cosineSimilarity(titleVector, queryVector)
  }

  _normalizeSearchText(value) {
    return (value || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
  }

  _trigramVector(value) {
    const compact = `  ${value.replace(/\s+/g, " ")}  `
    const vector = new Map()
    for (let index = 0; index <= compact.length - 3; index += 1) {
      const gram = compact.slice(index, index + 3)
      vector.set(gram, (vector.get(gram) || 0) + 1)
    }
    return vector
  }

  _cosineSimilarity(left, right) {
    let dot = 0
    let leftNorm = 0
    let rightNorm = 0

    left.forEach((value, key) => {
      leftNorm += value * value
      dot += value * (right.get(key) || 0)
    })
    right.forEach((value) => {
      rightNorm += value * value
    })

    if (!leftNorm || !rightNorm) return 0
    return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm))
  }

  _escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  async _parseJsonResponse(response, fallbackMessage) {
    const contentType = response.headers.get("content-type") || ""
    if (contentType.includes("application/json")) return await response.json()

    const body = await response.text()
    const normalized = body.trim().toLowerCase()
    const htmlLike = normalized.startsWith("<!doctype") || normalized.startsWith("<html")
    if (htmlLike) throw new Error("O servidor retornou HTML em vez de JSON ao criar a nota.")
    throw new Error(fallbackMessage)
  }

  _autosaveController() {
    const root = this.element.closest('[data-controller~="autosave"]')
    return root && this.application.getControllerForElementAndIdentifier(root, "autosave")
  }
}
