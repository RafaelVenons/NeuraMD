import { Controller } from "@hotwired/stimulus"
import { KeyboardShortcuts } from "lib/editor/keyboard_shortcuts"
import { LayoutManager } from "lib/editor/layout_manager"
import { RevisionManager } from "lib/editor/revision_manager"

// Orchestrates all sub-controllers: codemirror, preview, autosave, scroll-sync
export default class extends Controller {
  static targets = [
    "mainArea", "editorColumn", "editorPane", "previewPane", "previewContent",
    "contextPanel", "graphPanel", "backlinksPanel", "mentionsPanel", "contextMode",
    "previewResizeHandle", "contextResizeHandle",
    "titleInput", "langBadge", "saveStatus",
    "previewToggleBtn", "propertiesToggleBtn", "propertiesPanel",
    "typewriterBtn", "primaryActionButton",
    "revisionsButton", "revisionsMenu", "revisionsList", "typewriterExitBtn"
  ]
  static values = {
    autosaveUrl: String,
    revisionsUrl: String,
    convertMentionUrl: String,
    dismissMentionUrl: String,
    slug: String,
    title: String,
    language: String,
    focusTitle: Boolean,
    initialRevisionId: String,
    initialRevisionKind: String,
    headRevisionId: String
  }

  connect() {
    this._scrollSyncLock = false
    this._scrollCooldown = null
    this._aiStageActive = false
    this._onDocumentClick = this._handleDocumentClick.bind(this)

    this._layout = new LayoutManager(this._layoutElements(), `editor-layout:${this.slugValue}`)
    this._revisions = new RevisionManager({
      revisionsUrl: this.revisionsUrlValue,
      initialRevisionId: this.initialRevisionIdValue,
      initialRevisionKind: this.initialRevisionKindValue,
      headRevisionId: this.headRevisionIdValue,
      initialContent: this._initialEditorContent()
    }, {
      getCurrentContent: () => this._currentDisplayedContent(),
      syncMenuVisibility: (open) => this._syncRevisionsMenu(open),
      getListElement: () => this.hasRevisionsListTarget ? this.revisionsListTarget : null
    })

    this._boundPointerMove = (event) => this._layout.handlePointerMove(event)
    this._boundPointerUp = () => this._layout.finishResize()

    this._bindEditorEvents()
    this._bindKeyboardShortcuts()
    this._bindTitleInput()
    this._bindAutosaveStatus()
    this._bindAiStageState()
    this._bindNoteNavigation()
    this._layout.restore()
    this._scheduleInitialWorkspaceSync()
    this._syncPrimaryAction()
    this._focusTitleIfRequested()
    document.addEventListener("click", this._onDocumentClick)
    window.addEventListener("pointermove", this._boundPointerMove)
    window.addEventListener("pointerup", this._boundPointerUp)
  }

  disconnect() {
    this._shortcuts?.destroy()
    document.removeEventListener("click", this._onDocumentClick)
    window.removeEventListener("pointermove", this._boundPointerMove)
    window.removeEventListener("pointerup", this._boundPointerUp)
  }

  togglePreview() { this._layout.togglePreview() }
  showPreview() { this._layout.showPreview() }
  toggleProperties() { this._layout.toggleProperties() }
  updateContextMode() { this._layout.updateContextMode() }
  startPreviewResize(event) { this._layout.startPreviewResize(event) }
  startContextResize(event) { this._layout.startContextResize(event) }

  toggleTypewriter(event) {
    event?.preventDefault()
    this._toggleTypewriter()
  }

  enterAiReviewFocusMode() { this._layout.enterAiReviewFocus() }
  exitAiReviewFocusMode() { this._layout.exitAiReviewFocus() }

  async convertMention(event) {
    const btn = event.currentTarget
    const sourceSlug = btn.dataset.sourceSlug
    const matchedTerm = btn.dataset.matchedTerm

    btn.disabled = true
    btn.textContent = "..."

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const resp = await fetch(this.convertMentionUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ source_slug: sourceSlug, matched_term: matchedTerm })
      })
      const data = await resp.json()
      if (data.linked && this.hasMentionsPanelTarget) {
        this.mentionsPanelTarget.innerHTML = data.mentions_html
      }
    } catch (_) {
      btn.disabled = false
      btn.textContent = "Linkar"
    }
  }

  async dismissMention(event) {
    const btn = event.currentTarget
    const sourceSlug = btn.dataset.sourceSlug
    const matchedTerm = btn.dataset.matchedTerm

    btn.disabled = true
    btn.textContent = "..."

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const resp = await fetch(this.dismissMentionUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ source_slug: sourceSlug, matched_term: matchedTerm })
      })
      const data = await resp.json()
      if (data.dismissed && this.hasMentionsPanelTarget) {
        this.mentionsPanelTarget.innerHTML = data.mentions_html
      }
    } catch (_) {
      btn.disabled = false
      btn.textContent = "Ignorar"
    }
  }

  async toggleRevisions(event) {
    if (this._aiStageActive) return
    event.preventDefault()
    event.stopPropagation()
    await this._revisions.toggleMenu()
  }

  async handlePrimaryAction(event) {
    event.preventDefault()

    if (this._aiStageActive) {
      window.alert("Aplique ou descarte a sugestao da IA antes de salvar.")
      return
    }

    if (this._revisions.shouldShowRestore()) {
      await this._restoreSelectedRevision()
      return
    }

    await this._getAutosaveController()?.saveCheckpoint()
    this._revisions.onCheckpointSaved(this.headRevisionIdValue)
    this._syncPrimaryAction()
  }

  previewRevision(event) {
    const revision = this._revisions.previewRevision(event.currentTarget.dataset.revisionId)
    if (!revision) return
    this._applyContentToWorkspace(revision.content_markdown || "")
    this._previewRevisionProperties(revision.properties_data || {})
  }

  clearRevisionPreview(event) {
    if (this._revisions.clearPreview(event?.relatedTarget, this.hasRevisionsMenuTarget ? this.revisionsMenuTarget : null)) {
      this._applyContentToWorkspace(this._revisions.workingContent)
      this._getPropertiesPanelController()?.clearPreview()
    }
  }

  selectRevision(event) {
    event.preventDefault()
    const revision = this._revisions.selectRevision(event.currentTarget.dataset.revisionId)
    if (!revision) return
    this._applyContentToWorkspace(this._revisions.selectedContent)
    this._syncPrimaryAction()
  }

  // ── Editor events ─────────────────────────────────────────
  _bindEditorEvents() {
    this.element.addEventListener("codemirror:ready", (e) => {
      const initialContent = e.detail.editor.getValue()
      if (initialContent) this._onContentChange(initialContent)
    })

    this.element.addEventListener("codemirror:change", (e) => {
      const content = e.detail.value
      this._revisions.workingContent = content
      this._onContentChange(content)
      this._syncPrimaryAction()
    })

    this.element.addEventListener("codemirror:selectionchange", (e) => {
      if (!e.detail?.typewriterMode || !e.detail?.typewriter) return
      const preview = this._getPreviewController()
      preview?.setTypewriterMode(true)
      preview?.syncToTypewriter(e.detail.typewriter.currentLine, e.detail.typewriter.totalLines)
    })

    this.element.addEventListener("codemirror:scroll", (e) => {
      this._syncScrollEditorToPreview(e.detail.ratio)
    })

    this.element.addEventListener("preview:scroll", (e) => {
      this._syncScrollPreviewToEditor(e.detail.ratio)
    })

    this.element.addEventListener("autosave:statuschange", (e) => {
      this._onSaveStatus(e.detail)
    })

    this.element.addEventListener("table-editor:insert", (e) => {
      this._insertTable(e.detail)
    })

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

  _openTableEditor() {
    const cm = this._getCodemirrorController()
    if (!cm?.view) return

    const tableEl = document.querySelector("[data-controller~='table-editor']")
    if (!tableEl) return
    const tableCtrl = this.application.getControllerForElementAndIdentifier(tableEl, "table-editor")
    if (!tableCtrl) return

    const state = cm.view.state
    const pos = state.selection.main.head
    const doc = state.doc
    const curLine = doc.lineAt(pos)
    const isTableLine = (line) => line.text.trimStart().startsWith("|")

    if (isTableLine(curLine)) {
      let startLine = curLine
      while (startLine.number > 1) {
        const prev = doc.line(startLine.number - 1)
        if (!isTableLine(prev)) break
        startLine = prev
      }
      let endLine = curLine
      while (endLine.number < doc.lines) {
        const next = doc.line(endLine.number + 1)
        if (!isTableLine(next)) break
        endLine = next
      }
      const tableText = doc.sliceString(startLine.from, endLine.to)
      tableCtrl.openFromSelection(tableText, startLine.from, endLine.to)
    } else {
      tableCtrl.open()
    }
  }

  _insertTable({ markdown, editMode, startPos, endPos }) {
    const cm = this._getCodemirrorController()
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
  _bindNoteNavigation() {
    this.element.addEventListener("click", async (e) => {
      const link = e.target.closest(".preview-prose a.wikilink, .backlinks-panel a, .mentions-panel a.mention-link, .cm-content [data-note-href]")
      if (!link) return
      const isEditorTypewriterLink = !!link.closest(".cm-content")
      if (isEditorTypewriterLink && !(e.ctrlKey || e.metaKey)) return

      const href = link.getAttribute("href") || link.dataset.noteHref
      if (!href) return
      if (href.startsWith("#")) {
        e.preventDefault()
        const target = document.getElementById(href.slice(1))
        target?.scrollIntoView({ behavior: "smooth", block: "start" })
        return
      }

      const fragId = link.dataset.headingSlug || link.dataset.blockId
      if (fragId && href.includes("#")) {
        const linkPath = href.split("#")[0]
        const currentPath = window.location.pathname
        if (linkPath === currentPath || linkPath === "") {
          e.preventDefault()
          const target = document.getElementById(fragId)
          target?.scrollIntoView({ behavior: "smooth", block: "start" })
          return
        }
      }

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

  _applyTypewriterFocusMode(enabled) {
    if (enabled) this._layout.enterTypewriterFocus()
    else this._layout.exitTypewriterFocus()
  }

  // ── Keyboard shortcuts ───────────────────────────────────
  _bindKeyboardShortcuts() {
    this._shortcuts = new KeyboardShortcuts([
      { key: "E", ctrl: true, shift: true, action: () => this._toggleEmojiPicker() },
      { key: "P", ctrl: true, shift: true, action: () => this.toggleProperties() },
      { key: "p", ctrl: true, action: () => this.togglePreview() },
      { key: "f", ctrl: true, action: () => this._openDialog("find-replace-dialog") },
      { key: "h", ctrl: true, action: () => this._openDialogFocusReplace("find-replace-dialog") },
      { key: "g", ctrl: true, action: () => this._openDialog("jump-to-line-dialog") },
      { key: "\\", ctrl: true, action: () => this._toggleTypewriter() },
      { key: "y", ctrl: true, action: () => this._openTableEditor() },
      { key: "F1", action: () => this._toggleShortcutsHelp() },
      { key: "Escape", preventDefault: false, action: () => this._closeAllDialogs() }
    ], () => this._getCodemirrorController()?.isComposing())
    this._shortcuts.install()
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
    this._revisions.close()
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

  // ── Revisions helpers ────────────────────────────────────
  _handleDocumentClick(event) {
    if (this._revisions.isOpen && this.hasRevisionsMenuTarget && this.hasRevisionsButtonTarget) {
      const insideRevisions = this.revisionsMenuTarget.contains(event.target) || this.revisionsButtonTarget.contains(event.target)
      if (!insideRevisions) this._revisions.close()
    }
  }

  _syncRevisionsMenu(open) {
    if (!this.hasRevisionsMenuTarget || !this.hasRevisionsButtonTarget) return
    this.revisionsMenuTarget.classList.toggle("hidden", !open)
    this.revisionsButtonTarget.classList.toggle("toolbar-btn--active", open)
  }

  async _restoreSelectedRevision() {
    const restored = await this._revisions.restoreSelected(this.slugValue)
    if (!restored) return

    const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
    if (shell?.navigateTo) await shell.navigateTo(`/notes/${this.slugValue}`)
    else Turbo.visit(`/notes/${this.slugValue}`)
  }

  // ── Controller accessors ─────────────────────────────────
  _getAutosaveController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "autosave")
  }

  _getPreviewController() {
    return this.application.getControllerForElementAndIdentifier(
      this.previewPaneTarget, "preview"
    )
  }

  _getCodemirrorController() {
    return this.application.getControllerForElementAndIdentifier(
      this.editorPaneTarget, "codemirror"
    )
  }

  _getPropertiesPanelController() {
    const panel = document.querySelector("[data-controller~='properties-panel']")
    if (!panel) return null
    return this.application.getControllerForElementAndIdentifier(panel, "properties-panel")
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

  // ── Workspace helpers ────────────────────────────────────
  _initialEditorContent() {
    return this.editorPaneTarget.dataset.codemirrorInitialValueValue || ""
  }

  _currentDisplayedContent() {
    return this._getCodemirrorController()?.getValue() || this._revisions.workingContent || ""
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

  _previewRevisionProperties(props) {
    this._getPropertiesPanelController()?.previewProperties(props)
  }

  _syncPrimaryAction() {
    if (!this.hasPrimaryActionButtonTarget) return
    this._revisions.renderPrimaryAction(this.primaryActionButtonTarget)
  }

  hydrateNoteContext(payload) {
    const note = payload.note || {}
    const revision = payload.revision || {}
    const urls = payload.urls || {}

    this.slugValue = note.slug || this.slugValue
    this.titleValue = note.title || this.titleValue
    this.languageValue = note.detected_language || this.languageValue
    this.revisionsUrlValue = urls.revisions || this.revisionsUrlValue
    this.convertMentionUrlValue = urls.convert_mention || this.convertMentionUrlValue
    this.dismissMentionUrlValue = urls.dismiss_mention || this.dismissMentionUrlValue
    this.initialRevisionIdValue = revision.id || ""
    this.initialRevisionKindValue = revision.kind || ""
    this.headRevisionIdValue = note.head_revision_id || ""
    this._layout.updateStorageKey(`editor-layout:${this.slugValue}`)

    this._revisions.hydrateFromPayload(revision, note.head_revision_id)

    if (this.hasTitleInputTarget) this.titleInputTarget.value = note.title || ""
    if (this.hasLangBadgeTarget) {
      const lang = note.detected_language
      this.langBadgeTarget.textContent = lang || ""
      this.langBadgeTarget.classList.toggle("hidden", !lang)
    }
    if (this.hasBacklinksPanelTarget) this.backlinksPanelTarget.innerHTML = payload.html?.backlinks || ""
    if (this.hasMentionsPanelTarget) this.mentionsPanelTarget.innerHTML = payload.html?.mentions || ""

    this._revisions.close()
    this._applyContentToWorkspace(this._revisions.selectedContent)
    this._syncPrimaryAction()
  }

  _layoutElements() {
    return {
      mainArea: this.mainAreaTarget,
      editorColumn: this.editorColumnTarget,
      editorPane: this.editorPaneTarget,
      previewPane: this.previewPaneTarget,
      previewResizeHandle: this.previewResizeHandleTarget,
      previewToggleBtn: this.previewToggleBtnTarget,
      contextPanel: this.contextPanelTarget,
      contextResizeHandle: this.contextResizeHandleTarget,
      contextMode: this.contextModeTarget,
      graphPanel: this.graphPanelTarget,
      backlinksPanel: this.backlinksPanelTarget,
      mentionsPanel: this.hasMentionsPanelTarget ? this.mentionsPanelTarget : null,
      propertiesPanel: this.hasPropertiesPanelTarget ? this.propertiesPanelTarget : null,
      propertiesToggleBtn: this.hasPropertiesToggleBtnTarget ? this.propertiesToggleBtnTarget : null,
      typewriterExitBtn: this.hasTypewriterExitBtnTarget ? this.typewriterExitBtnTarget : null
    }
  }
}
