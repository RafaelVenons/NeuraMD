import { Controller } from "@hotwired/stimulus"

// Orchestrates all sub-controllers: codemirror, preview, autosave, scroll-sync
export default class extends Controller {
  static targets = [
    "mainArea", "editorPane", "previewPane", "previewContent",
    "contextPanel", "graphPanel", "backlinksPanel", "contextMode",
    "previewResizeHandle", "contextResizeHandle",
    "titleInput", "langBadge", "saveStatus",
    "previewToggleBtn", "typewriterBtn", "primaryActionButton",
    "revisionsButton", "revisionsMenu", "revisionsList", "typewriterExitBtn"
  ]
  static values = {
    autosaveUrl: String,
    revisionsUrl: String,
    slug: String,
    title: String,
    language: String,
    focusTitle: Boolean,
    initialRevisionId: String,
    initialRevisionKind: String,
    headRevisionId: String
  }

  connect() {
    this._previewVisible = true
    this._revisionsOpen = false
    this._revisionsLoaded = false
    this._revisionsById = new Map()
    this._scrollSyncLock = false
    this._scrollCooldown = null
    this._hoveredRevisionId = null
    this._selectedRevision = {
      id: this.initialRevisionIdValue || null,
      kind: this.initialRevisionKindValue || null,
      isHead: this.initialRevisionIdValue && this.initialRevisionIdValue === this.headRevisionIdValue
    }
    this._selectedRevisionContent = this._initialEditorContent()
    this._workingContent = this._selectedRevisionContent
    this._aiStageActive = false
    this._aiReviewFocusMode = false
    this._storedAiReviewLayout = null
    this._typewriterFocusMode = false
    this._storedTypewriterLayout = null
    this._onDocumentClick = this._handleDocumentClick.bind(this)
    this._layoutStorageKey = `editor-layout:${this.slugValue}`
    this._boundPointerMove = (event) => this._handlePointerMove(event)
    this._boundPointerUp = () => this._finishPointerResize()

    this._bindEditorEvents()
    this._bindKeyboardShortcuts()
    this._bindTitleInput()
    this._bindAutosaveStatus()
    this._bindAiStageState()
    this._bindNoteNavigation()
    this._restoreLayoutState()
    this._scheduleInitialWorkspaceSync()
    this._syncPrimaryAction()
    this._focusTitleIfRequested()
    document.addEventListener("click", this._onDocumentClick)
    window.addEventListener("pointermove", this._boundPointerMove)
    window.addEventListener("pointerup", this._boundPointerUp)
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
    document.removeEventListener("click", this._onDocumentClick)
    window.removeEventListener("pointermove", this._boundPointerMove)
    window.removeEventListener("pointerup", this._boundPointerUp)
  }

  togglePreview() {
    this._previewVisible = !this._previewVisible
    const pane = this.previewPaneTarget

    if (this._previewVisible) {
      pane.classList.remove("hidden")
      this.previewResizeHandleTarget.classList.remove("hidden")
      this.previewToggleBtnTarget.classList.add("toolbar-btn--active")
      this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      pane.classList.add("hidden")
      pane.style.flex = ""
      this.previewResizeHandleTarget.classList.add("hidden")
      this.previewToggleBtnTarget.classList.remove("toolbar-btn--active")
      this.editorPaneTarget.style.flex = "1 1 100%"
    }

    this._syncEditorWidthMode()
  }

  showPreview() {
    if (this._previewVisible) return

    this._previewVisible = true
    this.previewPaneTarget.classList.remove("hidden")
    this.previewResizeHandleTarget.classList.remove("hidden")
    this.previewToggleBtnTarget.classList.add("toolbar-btn--active")
    this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    this._syncEditorWidthMode()
  }

  toggleTypewriter(event) {
    event?.preventDefault()
    this._toggleTypewriter()
  }

  enterAiReviewFocusMode() {
    if (this._aiReviewFocusMode) return

    const tagSidebar = document.getElementById("tag-sidebar")
    this._storedAiReviewLayout = {
      previewVisible: this._previewVisible,
      previewPaneFlex: this.previewPaneTarget.style.flex,
      editorPaneHidden: this.editorPaneTarget.classList.contains("hidden"),
      resizeHandleHidden: this.previewResizeHandleTarget.classList.contains("hidden"),
      tagSidebarHidden: tagSidebar?.classList.contains("hidden") || false
    }

    this._aiReviewFocusMode = true
    this._previewVisible = true
    this.previewPaneTarget.classList.remove("hidden")
    this.previewPaneTarget.style.flex = "1 1 auto"
    this.editorPaneTarget.classList.add("hidden")
    this.previewResizeHandleTarget.classList.add("hidden")
    tagSidebar?.classList.add("hidden")
  }

  exitAiReviewFocusMode() {
    if (!this._aiReviewFocusMode) return

    const tagSidebar = document.getElementById("tag-sidebar")
    const stored = this._storedAiReviewLayout || {}

    this._aiReviewFocusMode = false
    this._storedAiReviewLayout = null

    this.editorPaneTarget.classList.toggle("hidden", !!stored.editorPaneHidden)
    this.previewResizeHandleTarget.classList.toggle("hidden", !!stored.resizeHandleHidden)
    tagSidebar?.classList.toggle("hidden", !!stored.tagSidebarHidden)

    this._previewVisible = stored.previewVisible !== false
    if (this._previewVisible) {
      this.previewPaneTarget.classList.remove("hidden")
      this.previewToggleBtnTarget.classList.add("toolbar-btn--active")
      this.previewPaneTarget.style.flex = stored.previewPaneFlex || ""
      if (!stored.previewPaneFlex) this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      this.previewPaneTarget.classList.add("hidden")
      this.previewToggleBtnTarget.classList.remove("toolbar-btn--active")
      this.previewPaneTarget.style.flex = stored.previewPaneFlex || ""
      this.editorPaneTarget.style.flex = "1 1 auto"
    }
  }

  startPreviewResize(event) {
    if (!this._previewVisible) return
    event.preventDefault()
    this._resizeMode = "preview"
    document.body.style.cursor = "col-resize"
  }

  startContextResize(event) {
    if (this.contextModeTarget.value === "hidden") return
    event.preventDefault()
    this._resizeMode = "context"
    document.body.style.cursor = "row-resize"
  }

  updateContextMode() {
    this._applyContextMode(this.contextModeTarget.value)
    this._persistLayoutState()
  }

  async toggleRevisions(event) {
    if (this._aiStageActive) return
    event.preventDefault()
    event.stopPropagation()

    this._revisionsOpen = !this._revisionsOpen
    this._syncRevisionsMenu()

    if (this._revisionsOpen && !this._revisionsLoaded) {
      await this._loadRevisions()
    }
  }

  async handlePrimaryAction(event) {
    event.preventDefault()

    if (this._aiStageActive) {
      window.alert("Aplique ou descarte a sugestao da IA antes de salvar.")
      return
    }

    if (this._shouldShowRestoreAction()) {
      await this._restoreSelectedRevision()
      return
    }

    await this._getAutosaveController()?.saveCheckpoint()
    this._selectedRevision = {
      id: this.headRevisionIdValue || this._selectedRevision.id,
      kind: "checkpoint",
      isHead: true
    }
    this._selectedRevisionContent = this._currentDisplayedContent()
    this._workingContent = this._selectedRevisionContent
    this._syncPrimaryAction()
  }

  previewRevision(event) {
    const revision = this._findRevision(event.currentTarget.dataset.revisionId)
    if (!revision) return

    this._hoveredRevisionId = revision.id
    this._applyContentToWorkspace(revision.content_markdown || "")
  }

  clearRevisionPreview(event) {
    if (!this._hoveredRevisionId) return
    if (event?.relatedTarget && this.revisionsMenuTarget.contains(event.relatedTarget)) return

    this._hoveredRevisionId = null
    this._applyContentToWorkspace(this._workingContent)
  }

  selectRevision(event) {
    event.preventDefault()
    const revision = this._findRevision(event.currentTarget.dataset.revisionId)
    if (!revision) return

    this._hoveredRevisionId = null
    this._selectedRevision = {
      id: revision.id,
      kind: "checkpoint",
      isHead: !!revision.is_head
    }
    this._selectedRevisionContent = revision.content_markdown || ""
    this._workingContent = this._selectedRevisionContent
    this._applyContentToWorkspace(this._selectedRevisionContent)
    this._closeRevisions()
    this._syncPrimaryAction()
  }

  // ── Editor events ─────────────────────────────────────────
  _bindEditorEvents() {
    // Render initial content as soon as the editor is ready (fires once on connect).
    // Without this, the preview stays blank until the user types something because
    // codemirror:change only fires on document mutations, not on initial load.
    this.element.addEventListener("codemirror:ready", (e) => {
      const initialContent = e.detail.editor.getValue()
      if (initialContent) this._onContentChange(initialContent)
    })

    // Listen for CodeMirror change events bubbling up
    this.element.addEventListener("codemirror:change", (e) => {
      const content = e.detail.value
      this._workingContent = content
      this._onContentChange(content)
      this._syncPrimaryAction()
    })

    this.element.addEventListener("codemirror:selectionchange", (e) => {
      if (!e.detail?.typewriterMode || !e.detail?.typewriter) return
      const preview = this._getPreviewController()
      preview?.setTypewriterMode(true)
      preview?.syncToTypewriter(e.detail.typewriter.currentLine, e.detail.typewriter.totalLines)
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

    // Listen for table-editor insertion
    this.element.addEventListener("table-editor:insert", (e) => {
      this._insertTable(e.detail)
    })

    // Listen for emoji-picker selection
    this.element.addEventListener("emoji-picker:selected", (e) => {
      const cm = this._getCodemirrorController()
      if (!cm) return
      cm.replaceSelection(e.detail.text)
      cm.focus()
    })

    this.element.addEventListener("typewriter:toggled", (e) => {
      const enabled = !!e.detail?.enabled
      this._applyTypewriterFocusMode(enabled)
      const preview = this._getPreviewController()
      preview?.setTypewriterMode(enabled)
      if (!enabled) return
      const sync = this._getCodemirrorController()?.getTypewriterSyncData()
      if (!sync) return
      preview?.syncToTypewriter(sync.currentLine, sync.totalLines)
    })
  }

  _bindAiStageState() {
    this.element.addEventListener("ai-review:stagechange", (event) => {
      this._aiStageActive = !!event.detail?.active
      this.primaryActionButtonTarget.disabled = this._aiStageActive
      this.revisionsButtonTarget.disabled = this._aiStageActive
      this.primaryActionButtonTarget.classList.toggle("opacity-25", this._aiStageActive)
      this.revisionsButtonTarget.classList.toggle("opacity-25", this._aiStageActive)
    })
  }

  _onContentChange(content) {
    this._getPreviewController()?.update(content)
  }

  _insertTable({ markdown, editMode, startPos, endPos }) {
    const cm = this._getCodeMirrorController()
    if (!cm?.view) return

    if (editMode) {
      cm.view.dispatch({
        changes: { from: startPos, to: endPos, insert: markdown },
        selection: { anchor: startPos + markdown.length }
      })
    } else {
      cm.replaceSelection(`\n${markdown}\n`)
    }
    cm.focus()
  }

  // ── Note navigation ──────────────────────────────────────
  // Intercept clicks on wiki-links (preview pane) and backlinks so the current
  // note is saved as a draft before Turbo navigates to the destination.
  _bindNoteNavigation() {
    this.element.addEventListener("click", async (e) => {
      const link = e.target.closest(".preview-prose a.wikilink, .backlinks-panel a, .cm-content [data-note-href]")
      if (!link) return
      const isEditorTypewriterLink = !!link.closest(".cm-content")
      if (isEditorTypewriterLink && !(e.ctrlKey || e.metaKey)) return

      const href = link.getAttribute("href") || link.dataset.noteHref
      if (!href || href.startsWith("#")) return

      e.preventDefault()
      const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
      if (shell?.navigateTo) {
        await shell.navigateTo(href)
        return
      }

      await this._getAutosaveController()?.saveDraftNow()
      Turbo.visit(href)
    })
  }

  _restoreLayoutState() {
    const stored = this._readLayoutState()
    this._previewWidthRatio = stored.previewWidthRatio || 0.5
    this._contextHeight = stored.contextHeight || 360

    if (stored.previewVisible === false) {
      this._previewVisible = false
      this.previewPaneTarget.classList.add("hidden")
      this.previewPaneTarget.style.flex = ""
      this.previewResizeHandleTarget.classList.add("hidden")
      this.previewToggleBtnTarget.classList.remove("toolbar-btn--active")
      this.editorPaneTarget.style.flex = "1 1 100%"
    } else {
      this.previewResizeHandleTarget.classList.remove("hidden")
      this.previewToggleBtnTarget.classList.add("toolbar-btn--active")
      this._applyPreviewWidth(this._previewWidthRatio)
    }

    this.contextModeTarget.value = stored.contextMode || "graph"
    this._applyContextHeight(this._contextHeight)
    this._applyContextMode(this.contextModeTarget.value)
    this._syncEditorWidthMode()
  }

  _applyTypewriterFocusMode(enabled) {
    if (enabled) {
      if (!this._typewriterFocusMode) {
        this._storedTypewriterLayout = {
          previewVisible: this._previewVisible,
          previewPaneFlex: this.previewPaneTarget.style.flex,
          contextMode: this.contextModeTarget.value,
          contextHeight: this._contextHeight
        }
      }

      this._typewriterFocusMode = true
      this.showPreview()
      this.contextModeTarget.value = "hidden"
      this._applyContextMode("hidden")
      this.previewPaneTarget.style.flex = "1 1 auto"
      this.previewResizeHandleTarget.classList.add("hidden")
      if (this.hasTypewriterExitBtnTarget) {
        this.typewriterExitBtnTarget.setAttribute("aria-hidden", "false")
      }
      return
    }

    const stored = this._storedTypewriterLayout || {}
    this._typewriterFocusMode = false
    if (this.hasTypewriterExitBtnTarget) {
      this.typewriterExitBtnTarget.setAttribute("aria-hidden", "true")
    }

    this.contextModeTarget.value = stored.contextMode || this.contextModeTarget.value || "graph"
    this._contextHeight = stored.contextHeight || this._contextHeight
    this._applyContextMode(this.contextModeTarget.value)

    this._previewVisible = stored.previewVisible !== false
    if (this._previewVisible) {
      this.previewPaneTarget.classList.remove("hidden")
      this.previewResizeHandleTarget.classList.remove("hidden")
      this.previewPaneTarget.style.flex = stored.previewPaneFlex || ""
      if (!stored.previewPaneFlex) this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      this.previewPaneTarget.classList.add("hidden")
      this.previewResizeHandleTarget.classList.add("hidden")
      this.previewPaneTarget.style.flex = stored.previewPaneFlex || ""
      this.editorPaneTarget.style.flex = "1 1 100%"
      this.previewToggleBtnTarget.classList.remove("toolbar-btn--active")
    }

    this._storedTypewriterLayout = null
    this._persistLayoutState()
  }

  _applyPreviewWidth(ratio) {
    if (!this._previewVisible) return
    const bounded = Math.min(Math.max(ratio, 0.25), 0.75)
    this._previewWidthRatio = bounded
    this.previewPaneTarget.style.flex = `0 0 ${bounded * 100}%`
    this.editorPaneTarget.style.flex = "1 1 auto"
    this._syncEditorWidthMode()
  }

  _syncEditorWidthMode() {
    this.editorPaneTarget.classList.toggle("editor-pane--full-width", !this._previewVisible && !this._aiReviewFocusMode)
  }

  _applyContextHeight(height) {
    const bounded = Math.min(Math.max(height, 140), window.innerHeight * 0.72)
    this._contextHeight = bounded
    if (this.contextModeTarget.value === "hidden") {
      this.contextPanelTarget.style.flex = "0 0 auto"
      return
    }

    this.contextPanelTarget.style.flex = `0 0 ${bounded}px`
  }

  _applyContextMode(mode) {
    const isHidden = mode === "hidden"
    const showBacklinks = mode === "backlinks"

    this.contextPanelTarget.classList.toggle("note-context-panel--collapsed", isHidden)
    this.contextResizeHandleTarget.classList.toggle("hidden", isHidden)
    this.graphPanelTarget.classList.toggle("hidden", showBacklinks || isHidden)
    this.backlinksPanelTarget.classList.toggle("hidden", !showBacklinks || isHidden)

    if (isHidden) this.contextPanelTarget.style.flex = "0 0 auto"
    else this._applyContextHeight(this._contextHeight)
  }

  _handlePointerMove(event) {
    if (!this._resizeMode) return

    if (this._resizeMode === "preview") {
      const rect = this.mainAreaTarget.getBoundingClientRect()
      const ratio = (rect.right - event.clientX) / Math.max(rect.width, 1)
      this._applyPreviewWidth(ratio)
      return
    }

    if (this._resizeMode === "context") {
      const previewRect = this.previewPaneTarget.getBoundingClientRect()
      const height = previewRect.bottom - event.clientY
      this._applyContextHeight(height)
    }
  }

  _finishPointerResize() {
    if (!this._resizeMode) return
    this._resizeMode = null
    document.body.style.cursor = ""
    this._persistLayoutState()
  }

  _persistLayoutState() {
    const payload = {
      previewWidthRatio: this._previewWidthRatio,
      contextHeight: this._contextHeight,
      contextMode: this.contextModeTarget.value,
      previewVisible: this._previewVisible
    }
    window.localStorage?.setItem(this._layoutStorageKey, JSON.stringify(payload))
  }

  _readLayoutState() {
    try {
      return JSON.parse(window.localStorage?.getItem(this._layoutStorageKey) || "{}")
    } catch {
      return {}
    }
  }

  _getAutosaveController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "autosave")
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
    if (this._getCodemirrorController()?.isTypewriterMode()) return
    this._scrollSyncLock = true
    this._getPreviewController()?.setScrollRatio(ratio)
    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._scrollSyncLock = false }, 400)
  }

  _syncScrollPreviewToEditor(ratio) {
    if (this._scrollSyncLock) return
    if (this._getCodemirrorController()?.isTypewriterMode()) return
    this._scrollSyncLock = true
    this._getCodemirrorController()?.setScrollRatio(ratio)
    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._scrollSyncLock = false }, 400)
  }

  // ── Keyboard shortcuts ───────────────────────────────────
  _bindKeyboardShortcuts() {
    this._keyHandler = (e) => {
      if (e.isComposing || e.keyCode === 229 || this._getCodemirrorController()?.isComposing()) return
      const ctrl = e.ctrlKey || e.metaKey

      if (ctrl && e.shiftKey && e.key === "E") {
        e.preventDefault()
        this._toggleEmojiPicker()
        return
      }
      if (ctrl && e.key === "p") {
        e.preventDefault()
        this.togglePreview()
      }
      if (ctrl && e.key === "f") {
        e.preventDefault()
        this._openDialog("find-replace-dialog")
      }
      if (ctrl && e.key === "h") {
        e.preventDefault()
        this._openDialogFocusReplace("find-replace-dialog")
      }
      if (ctrl && e.key === "g") {
        e.preventDefault()
        this._openDialog("jump-to-line-dialog")
      }
      if (ctrl && e.key === "\\") {
        e.preventDefault()
        this._toggleTypewriter()
      }
      if (e.key === "F1") {
        e.preventDefault()
        this._toggleShortcutsHelp()
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

  _openDialogFocusReplace(id) {
    const dialog = document.getElementById(id)
    if (!dialog) return
    dialog.classList.remove("hidden")
    const replaceInput = dialog.querySelector("[data-find-replace-target='replaceInput']")
    if (replaceInput) replaceInput.focus()
    else dialog.querySelector("input")?.focus()
  }

  _toggleEmojiPicker() {
    const el = document.querySelector("[data-controller~='emoji-picker']")
    if (!el) return
    const ctrl = this.application.getControllerForElementAndIdentifier(el, "emoji-picker")
    if (!ctrl) return
    const dialog = el.querySelector("dialog")
    if (dialog?.open) ctrl.close()
    else ctrl.open()
  }

  _toggleTypewriter() {
    const el = document.querySelector("[data-controller~='typewriter']")
    if (!el) return
    const ctrl = this.application.getControllerForElementAndIdentifier(el, "typewriter")
    ctrl?.toggle()
  }

  _toggleShortcutsHelp() {
    const dialog = document.getElementById("shortcuts-help-dialog")
    if (!dialog) return
    if (dialog.open) dialog.close()
    else dialog.showModal()
  }

  _closeAllDialogs() {
    document.getElementById("find-replace-dialog")?.classList.add("hidden")
    document.getElementById("jump-to-line-dialog")?.classList.add("hidden")
    document.getElementById("shortcuts-help-dialog")?.close()
    this._closeRevisions()
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

  _focusTitleIfRequested() {
    if (!this.focusTitleValue || !this.hasTitleInputTarget) return

    requestAnimationFrame(() => {
      this.titleInputTarget.focus()
      this.titleInputTarget.select()
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
      rascunho: { text: "Rascunho salvo", cls: "text-blue-300" },
      pendente: { text: "Pendente", cls: "text-gray-500" },
      erro: { text: "Erro ao salvar", cls: "text-red-400" }
    }
    const { text, cls } = map[state] || { text: "—", cls: "text-gray-500" }
    el.textContent = text
    el.className = `flex-shrink-0 text-xs ${cls}`
  }

  async _loadRevisions() {
    if (!this.hasRevisionsListTarget) return

    this.revisionsListTarget.innerHTML = `
      <li class="px-3 py-2 text-xs" style="color: var(--theme-text-faint)">Carregando...</li>
    `

    try {
      const response = await fetch(this.revisionsUrlValue, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const revisions = await response.json()
      this._revisionsLoaded = true
      this._revisionsById = new Map(revisions.map((revision) => [String(revision.id), revision]))
      this._renderRevisions(revisions)
    } catch (error) {
      console.error("Revisions load error:", error)
      this.revisionsListTarget.innerHTML = `
        <li class="px-3 py-2 text-xs text-red-400">Nao foi possivel carregar as versoes.</li>
      `
    }
  }

  _renderRevisions(revisions) {
    if (!this.hasRevisionsListTarget) return

    if (!revisions.length) {
      this.revisionsListTarget.innerHTML = `
        <li class="px-3 py-2 text-xs" style="color: var(--theme-text-faint)">Nenhuma versao salva.</li>
      `
      return
    }

    this.revisionsListTarget.innerHTML = revisions.map((revision) => {
      const createdAt = new Date(revision.created_at).toLocaleString("pt-BR", {
        dateStyle: "short",
        timeStyle: "short"
      })
      return `
        <li class="border-b last:border-b-0"
            style="border-color: var(--toolbar-border)">
          <button type="button"
                  class="revision-entry w-full text-left ${revision.is_head ? "is-head" : ""}"
                  data-revision-id="${revision.id}"
                  data-action="mouseenter->editor#previewRevision click->editor#selectRevision">
            <span class="min-w-0 block">
              <span class="flex items-center gap-2">
                <span class="text-xs font-semibold text-gray-200">${createdAt}</span>
                ${revision.is_head ? '<span class="rounded px-1.5 py-0.5 text-[10px] font-semibold text-green-200" style="background: rgba(34, 197, 94, 0.16)">Atual</span>' : ""}
              </span>
            </span>
          </button>
        </li>
      `
    }).join("")
  }

  _handleDocumentClick(event) {
    if (this._revisionsOpen && this.hasRevisionsMenuTarget && this.hasRevisionsButtonTarget) {
      const insideRevisions = this.revisionsMenuTarget.contains(event.target) || this.revisionsButtonTarget.contains(event.target)
      if (!insideRevisions) this._closeRevisions()
    }
  }

  _closeRevisions() {
    if (!this._revisionsOpen) return
    this.clearRevisionPreview()
    this._revisionsOpen = false
    this._syncRevisionsMenu()
  }

  _syncRevisionsMenu() {
    if (!this.hasRevisionsMenuTarget || !this.hasRevisionsButtonTarget) return
    this.revisionsMenuTarget.classList.toggle("hidden", !this._revisionsOpen)
    this.revisionsButtonTarget.classList.toggle("toolbar-btn--active", this._revisionsOpen)
  }

  _initialEditorContent() {
    return this.editorPaneTarget.dataset.codemirrorInitialValueValue || ""
  }

  _currentDisplayedContent() {
    return this._getCodemirrorController()?.getValue() || this._workingContent || ""
  }

  _applyContentToWorkspace(content) {
    this._getCodemirrorController()?.setValue(content, { silent: true })
    this._getPreviewController()?.update(content)
  }

  _scheduleInitialWorkspaceSync() {
    requestAnimationFrame(() => {
      this._applyContentToWorkspace(this._currentDisplayedContent())
    })
  }

  _findRevision(revisionId) {
    if (!revisionId) return null
    return this._revisionsById.get(String(revisionId)) || null
  }

  _hasPendingEdits() {
    return this._workingContent !== this._selectedRevisionContent
  }

  _shouldShowRestoreAction() {
    return !!(
      this._selectedRevision?.id &&
      this._selectedRevision?.kind === "checkpoint" &&
      !this._selectedRevision?.isHead &&
      !this._hasPendingEdits()
    )
  }

  async _restoreSelectedRevision() {
    const revisionId = this._selectedRevision?.id
    if (!revisionId) return
    if (!window.confirm("Restaurar esta versão como a versão atual?")) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(`/notes/${this.slugValue}/revisions/${revisionId}/restore`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        }
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this._revisionsLoaded = false
      this._closeRevisions()
      const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
      if (shell?.navigateTo) await shell.navigateTo(`/notes/${this.slugValue}`)
      else Turbo.visit(`/notes/${this.slugValue}`)
    } catch (error) {
      console.error("Revision restore error:", error)
    }
  }

  hydrateNoteContext(payload) {
    const note = payload.note || {}
    const revision = payload.revision || {}
    const urls = payload.urls || {}

    this.slugValue = note.slug || this.slugValue
    this.titleValue = note.title || this.titleValue
    this.languageValue = note.detected_language || this.languageValue
    this.revisionsUrlValue = urls.revisions || this.revisionsUrlValue
    this.initialRevisionIdValue = revision.id || ""
    this.initialRevisionKindValue = revision.kind || ""
    this.headRevisionIdValue = note.head_revision_id || ""
    this._layoutStorageKey = `editor-layout:${this.slugValue}`
    this._revisionsOpen = false
    this._revisionsLoaded = false
    this._revisionsById = new Map()
    this._hoveredRevisionId = null
    this._selectedRevision = {
      id: revision.id || null,
      kind: revision.kind || null,
      isHead: revision.id && revision.id === note.head_revision_id
    }
    this._selectedRevisionContent = revision.content_markdown || ""
    this._workingContent = this._selectedRevisionContent

    if (this.hasTitleInputTarget) this.titleInputTarget.value = note.title || ""
    if (this.hasLangBadgeTarget) {
      const lang = note.detected_language
      this.langBadgeTarget.textContent = lang || ""
      this.langBadgeTarget.classList.toggle("hidden", !lang)
    }
    if (this.hasBacklinksPanelTarget) this.backlinksPanelTarget.innerHTML = payload.html?.backlinks || ""

    this._closeRevisions()
    this._applyContentToWorkspace(this._selectedRevisionContent)
    this._syncPrimaryAction()
  }

  _syncPrimaryAction() {
    if (!this.hasPrimaryActionButtonTarget) return

    const isRestore = this._shouldShowRestoreAction()
    const button = this.primaryActionButtonTarget

    button.title = isRestore ? "Restaurar esta versao" : "Salvar versão (checkpoint)"
    button.style.background = isRestore ? "#dc2626" : "var(--theme-accent)"
    button.innerHTML = isRestore ? `
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M3 12a9 9 0 109-9"/><path d="M3 3v6h6"/>
      </svg>
      Restaurar
    ` : `
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/>
        <polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/>
      </svg>
      Salvar
    `
  }
}
