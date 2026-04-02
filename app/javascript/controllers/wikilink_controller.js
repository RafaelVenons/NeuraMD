import { Controller } from "@hotwired/stimulus"
import { normalizeSearchText, trigramScore } from "lib/trigram_search"
import { DropdownRenderer } from "lib/wikilink/dropdown_renderer"
import { buildWikilinkMarkup } from "lib/wikilink/markup_builder"

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
  static FULL_RE    = /\[\[([^\]|]+)\|([a-z]+:)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:#([a-z0-9_-]+)|\^([a-zA-Z0-9-]+))?\]\]/gi

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
    this._dropdownRenderer = new DropdownRenderer(this.dropdownTarget, this.constructor.ROLE_LABEL)

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
      this._resolvePromise(this._promiseTitle)
      this._detectCursorInLink(value, cursorPos)
      return
    }

    // Detect heading sub-picker: [[Display|role:uuid#partial
    const headingTrigger = lineUpToCursor.match(
      /\[\[([^\]|]+)\|(?:([a-z]+):)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})#([^\]#]*)$/i
    )

    if (headingTrigger) {
      this._dropdownMode = "headings"
      this._headingNoteId = headingTrigger[3]
      this._headingDisplay = headingTrigger[1]
      this._headingRole = headingTrigger[2] || null
      this._headingQuery = headingTrigger[4]
      this._insertStart = cursorPos - headingTrigger[0].length
      this._scheduleHeadingSearch(this._headingNoteId, this._headingQuery)
      this._detectCursorInLink(value, cursorPos)
      return
    }

    // Detect block sub-picker: [[Display|role:uuid^partial
    const blockTrigger = lineUpToCursor.match(
      /\[\[([^\]|]+)\|(?:([a-z]+):)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\^([^\]^]*)$/i
    )

    if (blockTrigger) {
      this._dropdownMode = "blocks"
      this._blockNoteId = blockTrigger[3]
      this._blockDisplay = blockTrigger[1]
      this._blockRole = blockTrigger[2] || null
      this._blockQuery = blockTrigger[4]
      this._insertStart = cursorPos - blockTrigger[0].length
      this._scheduleBlockSearch(this._blockNoteId, this._blockQuery)
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
          headingSlug: match[4] || null,
          blockId: match[5] || null,
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
            else if (this._dropdownMode === "disambiguate") this._selectDisambiguation(this._suggestions[this._activeIndex])
            else if (this._dropdownMode === "headings") this._insertHeadingSuggestion(this._suggestions[this._activeIndex])
            else if (this._dropdownMode === "blocks") this._insertBlockSuggestion(this._suggestions[this._activeIndex])
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
    const markup = buildWikilinkMarkup({
      display: this._focusedLink.display, role: nextRole,
      uuid: this._focusedLink.uuid, headingSlug: this._focusedLink.headingSlug,
      blockId: this._focusedLink.blockId
    })
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

  _scheduleHeadingSearch(noteId, query) {
    clearTimeout(this._debounceTimer)
    this._showHeadingLoading()
    this._debounceTimer = setTimeout(() => this._fetchHeadingSuggestions(noteId, query), 75)
  }

  async _fetchHeadingSuggestions(noteId, query) {
    try {
      if (this._dropdownMode !== "headings") return
      const params = new URLSearchParams({ mode: "headings", note_id: noteId })
      if (query) params.set("q", query)
      const url = `${this.searchUrlValue}?${params.toString()}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const headings = await response.json()
      if (this._dropdownMode !== "headings" || this._headingNoteId !== noteId) return
      this._suggestions = headings.map(h => ({
        ...h,
        title: `${"#".repeat(h.level)} ${h.text}`,
        label: `${"  ".repeat(h.level - 1)}${h.text}`,
        id: h.slug
      }))
      this._activeIndex = this._suggestions.length > 0 ? 0 : -1
      this._renderDropdown()
    } catch (_) {
      this._closeDropdown()
    }
  }

  _showHeadingLoading() {
    this._suggestions = [{ label: "Buscando headings...", description: "Filtrando headings da nota.", loading: true }]
    this._activeIndex = -1
    this._renderDropdown()
  }

  _insertHeadingSuggestion(heading) {
    if (!heading || heading.loading) return
    const markup = buildWikilinkMarkup({
      display: `${this._headingDisplay}#${heading.text}`,
      role: this._headingRole, uuid: this._headingNoteId, headingSlug: heading.slug
    })
    this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
      detail: { markup, insertStart: this._insertStart },
      bubbles: true
    }))
    this._closeDropdown()
  }

  _scheduleBlockSearch(noteId, query) {
    clearTimeout(this._debounceTimer)
    this._suggestions = [{ label: "Buscando blocos...", description: "Filtrando blocos da nota.", loading: true }]
    this._activeIndex = -1
    this._renderDropdown()
    this._debounceTimer = setTimeout(() => this._fetchBlockSuggestions(noteId, query), 75)
  }

  async _fetchBlockSuggestions(noteId, query) {
    try {
      if (this._dropdownMode !== "blocks") return
      const params = new URLSearchParams({ mode: "blocks", note_id: noteId })
      if (query) params.set("q", query)
      const url = `${this.searchUrlValue}?${params.toString()}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const blocks = await response.json()
      if (this._dropdownMode !== "blocks" || this._blockNoteId !== noteId) return
      this._suggestions = blocks.map(b => ({
        ...b,
        title: b.content,
        label: `${b.block_type}: ${b.content}`,
        id: b.block_id
      }))
      this._activeIndex = this._suggestions.length > 0 ? 0 : -1
      this._renderDropdown()
    } catch (_) {
      this._closeDropdown()
    }
  }

  _insertBlockSuggestion(block) {
    if (!block || block.loading) return
    const excerpt = block.content.slice(0, 30).trim()
    const markup = buildWikilinkMarkup({
      display: `${this._blockDisplay}^${excerpt}`,
      role: this._blockRole, uuid: this._blockNoteId, blockId: block.block_id
    })
    this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
      detail: { markup, insertStart: this._insertStart },
      bubbles: true
    }))
    this._closeDropdown()
  }

  async _resolvePromise(title) {
    if (!title) {
      this._showPromiseActions()
      return
    }

    this._dropdownMode = "resolving"
    this._suggestions = [{ label: "Resolvendo...", description: "Verificando se a nota já existe.", loading: true }]
    this._activeIndex = -1
    this._renderDropdown()

    try {
      const params = new URLSearchParams({ q: title, mode: "resolve" })
      if (this.currentNoteIdValue) params.set("exclude_id", this.currentNoteIdValue)
      const url = `${this.searchUrlValue}?${params.toString()}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) {
        this._showPromiseActions()
        return
      }
      const data = await response.json()

      if (data.status === "resolved" && data.notes.length === 1) {
        this._autoResolvePromise(data.notes[0])
      } else if (data.status === "ambiguous" && data.notes.length > 1) {
        this._showDisambiguation(data.notes)
      } else {
        this._showPromiseActions()
      }
    } catch (_) {
      this._showPromiseActions()
    }
  }

  _autoResolvePromise(note) {
    const markup = buildWikilinkMarkup({ display: note.title, role: this._currentRole, uuid: note.id })
    this.element.dispatchEvent(new CustomEvent("wikilink:insert", {
      detail: { markup, insertStart: this._insertStart },
      bubbles: true
    }))
    this._closeDropdown()
    this._autosaveController()?.saveDraftNow?.()
  }

  _showDisambiguation(notes) {
    this._dropdownMode = "disambiguate"
    this._suggestions = [
      ...notes.map(n => ({ ...n, action: "pick" })),
      { action: "create", label: "Criar nova nota", description: "Nenhuma das opções acima." }
    ]
    this._activeIndex = 0
    this._renderDropdown()
  }

  _selectDisambiguation(option) {
    if (!option) return
    if (option.action === "create") {
      this._showPromiseActions()
      return
    }
    this._autoResolvePromise(option)
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
    const markup = buildWikilinkMarkup({ display: note.title, role: this._currentRole, uuid: note.id })
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

      const markup = buildWikilinkMarkup({ display: data.note_title, role: this._currentRole, uuid: data.note_id })
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
    if (this._suggestions.length === 0) {
      this._closeDropdown()
      return
    }

    this._dropdownRenderer.render(
      this._suggestions,
      this._activeIndex,
      this._currentRole,
      (i, item) => {
        this._activeIndex = i
        if (this._dropdownMode === "promise") this._selectPromiseAction(item)
        else if (this._dropdownMode === "disambiguate") this._selectDisambiguation(item)
        else if (this._dropdownMode === "headings") this._insertHeadingSuggestion(item)
        else if (this._dropdownMode === "blocks") this._insertBlockSuggestion(item)
        else this._insertSuggestion(item)
      },
      this._escapeHtml.bind(this)
    )

    this._dropdownRenderer.position(this._insertStart, this._cm?.view, this.element.getBoundingClientRect())
    this._dropdownRenderer.scrollActiveIntoView()
  }

  // ── Positioning ──────────────────────────────────────────

  _positionDropdown() {
    this._dropdownRenderer.position(this._insertStart, this._cm?.view, this.element.getBoundingClientRect())
  }

  _scrollActiveSuggestionIntoView() {
    this._dropdownRenderer.scrollActiveIntoView()
  }

  // ── State ────────────────────────────────────────────────

  _isDropdownOpen() {
    return this._dropdownRenderer?.isOpen() ?? false
  }

  _closeDropdown({ preserveFocus = false } = {}) {
    this._dropdownRenderer?.close()
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
    const normalizedQuery = normalizeSearchText(query)
    if (!normalizedQuery) return suggestions

    return [...suggestions]
      .map((note) => ({
        note,
        score: Math.max(
          trigramScore(note.title, query),
          note.matched_alias ? trigramScore(note.matched_alias, query) : 0
        )
      }))
      .filter(({ score }) => score > 0)
      .sort((left, right) => {
        if (right.score !== left.score) return right.score - left.score
        return left.note.title.localeCompare(right.note.title, "pt-BR")
      })
      .map(({ note }) => note)
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
