export class LayoutManager {
  constructor(elements, storageKey) {
    this._el = elements
    this._storageKey = storageKey
    this._previewVisible = true
    this._propertiesVisible = false
    this._previewWidthRatio = 0.5
    this._contextHeight = 360
    this._resizeMode = null
    this._typewriterFocusMode = false
    this._storedTypewriterLayout = null
    this._aiReviewFocusMode = false
    this._storedAiReviewLayout = null
  }

  get previewVisible() { return this._previewVisible }
  get propertiesVisible() { return this._propertiesVisible }

  restore() {
    const stored = this._readState()
    this._previewWidthRatio = stored.previewWidthRatio || 0.5
    this._contextHeight = stored.contextHeight || 360

    if (stored.previewVisible === false) {
      this._previewVisible = false
      this._el.previewPane.classList.add("hidden")
      this._el.previewPane.style.flex = ""
      this._el.previewResizeHandle.classList.add("hidden")
      this._el.previewToggleBtn.classList.remove("toolbar-btn--active")
      this._el.editorPane.style.flex = "1 1 100%"
    } else {
      this._el.previewResizeHandle.classList.remove("hidden")
      this._el.previewToggleBtn.classList.add("toolbar-btn--active")
      this._applyPreviewWidth(this._previewWidthRatio)
    }

    this._el.contextMode.value = stored.contextMode || "graph"
    this._applyContextHeight(this._contextHeight)
    this.applyContextMode(this._el.contextMode.value)

    if (stored.propertiesVisible && this._el.propertiesPanel) {
      this._propertiesVisible = true
      this._el.propertiesPanel.classList.remove("hidden")
      if (this._el.propertiesToggleBtn) this._el.propertiesToggleBtn.classList.add("toolbar-btn--active")
    }

    this._syncEditorWidthMode()
  }

  togglePreview() {
    this._previewVisible = !this._previewVisible

    if (this._previewVisible) {
      this._el.previewPane.classList.remove("hidden")
      this._el.previewResizeHandle.classList.remove("hidden")
      this._el.previewToggleBtn.classList.add("toolbar-btn--active")
      this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      this._el.previewPane.classList.add("hidden")
      this._el.previewPane.style.flex = ""
      this._el.previewResizeHandle.classList.add("hidden")
      this._el.previewToggleBtn.classList.remove("toolbar-btn--active")
      this._el.editorPane.style.flex = "1 1 100%"
    }

    this._syncEditorWidthMode()
  }

  showPreview() {
    if (this._previewVisible) return
    this._previewVisible = true
    this._el.previewPane.classList.remove("hidden")
    this._el.previewResizeHandle.classList.remove("hidden")
    this._el.previewToggleBtn.classList.add("toolbar-btn--active")
    this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    this._syncEditorWidthMode()
  }

  toggleProperties() {
    this._propertiesVisible = !this._propertiesVisible
    if (this._el.propertiesPanel) {
      this._el.propertiesPanel.classList.toggle("hidden", !this._propertiesVisible)
    }
    if (this._el.propertiesToggleBtn) {
      this._el.propertiesToggleBtn.classList.toggle("toolbar-btn--active", this._propertiesVisible)
    }
    this._persist()
  }

  applyContextMode(mode) {
    const isHidden = mode === "hidden"
    const showBacklinks = mode === "backlinks"
    const showMentions = mode === "mentions"

    this._el.contextPanel.classList.toggle("note-context-panel--collapsed", isHidden)
    this._el.contextResizeHandle.classList.toggle("hidden", isHidden)
    this._el.graphPanel.classList.toggle("hidden", showBacklinks || showMentions || isHidden)
    this._el.backlinksPanel.classList.toggle("hidden", !showBacklinks || isHidden)
    if (this._el.mentionsPanel) {
      this._el.mentionsPanel.classList.toggle("hidden", !showMentions || isHidden)
    }

    if (isHidden) this._el.contextPanel.style.flex = "0 0 auto"
    else this._applyContextHeight(this._contextHeight)
  }

  updateContextMode() {
    this.applyContextMode(this._el.contextMode.value)
    this._persist()
  }

  startPreviewResize(event) {
    if (!this._previewVisible) return
    event.preventDefault()
    this._resizeMode = "preview"
    document.body.style.cursor = "col-resize"
  }

  startContextResize(event) {
    if (this._el.contextMode.value === "hidden") return
    event.preventDefault()
    this._resizeMode = "context"
    document.body.style.cursor = "row-resize"
  }

  handlePointerMove(event) {
    if (!this._resizeMode) return

    if (this._resizeMode === "preview") {
      const rect = this._el.mainArea.getBoundingClientRect()
      const ratio = (rect.right - event.clientX) / Math.max(rect.width, 1)
      this._applyPreviewWidth(ratio)
      return
    }

    if (this._resizeMode === "context") {
      const colRect = this._el.editorColumn.getBoundingClientRect()
      const height = colRect.bottom - event.clientY
      this._applyContextHeight(height)
    }
  }

  finishResize() {
    if (!this._resizeMode) return
    this._resizeMode = null
    document.body.style.cursor = ""
    this._persist()
  }

  enterTypewriterFocus() {
    if (!this._typewriterFocusMode) {
      this._storedTypewriterLayout = {
        previewVisible: this._previewVisible,
        propertiesVisible: this._propertiesVisible,
        previewPaneFlex: this._el.previewPane.style.flex,
        contextMode: this._el.contextMode.value,
        contextHeight: this._contextHeight
      }
    }

    this._typewriterFocusMode = true
    this._previewVisible = false
    this._el.previewPane.classList.add("hidden")
    this._el.contextMode.value = "hidden"
    this.applyContextMode("hidden")
    this._el.previewPane.style.flex = this._storedTypewriterLayout?.previewPaneFlex || ""
    this._el.previewResizeHandle.classList.add("hidden")
    this._el.editorPane.style.flex = "1 1 100%"
    this._el.previewToggleBtn.classList.remove("toolbar-btn--active")
    if (this._el.propertiesPanel) this._el.propertiesPanel.classList.add("hidden")
    if (this._el.propertiesToggleBtn) this._el.propertiesToggleBtn.classList.remove("toolbar-btn--active")
    if (this._el.typewriterExitBtn) {
      this._el.typewriterExitBtn.setAttribute("aria-hidden", "false")
    }
  }

  exitTypewriterFocus() {
    const stored = this._storedTypewriterLayout || {}
    this._typewriterFocusMode = false
    if (this._el.typewriterExitBtn) {
      this._el.typewriterExitBtn.setAttribute("aria-hidden", "true")
    }

    this._el.contextMode.value = stored.contextMode || this._el.contextMode.value || "graph"
    this._contextHeight = stored.contextHeight || this._contextHeight
    this.applyContextMode(this._el.contextMode.value)

    this._previewVisible = stored.previewVisible !== false
    if (this._previewVisible) {
      this._el.previewPane.classList.remove("hidden")
      this._el.previewResizeHandle.classList.remove("hidden")
      this._el.previewPane.style.flex = stored.previewPaneFlex || ""
      if (!stored.previewPaneFlex) this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      this._el.previewPane.classList.add("hidden")
      this._el.previewResizeHandle.classList.add("hidden")
      this._el.previewPane.style.flex = stored.previewPaneFlex || ""
      this._el.editorPane.style.flex = "1 1 100%"
      this._el.previewToggleBtn.classList.remove("toolbar-btn--active")
    }

    if (stored.propertiesVisible && this._el.propertiesPanel) {
      this._propertiesVisible = true
      this._el.propertiesPanel.classList.remove("hidden")
      if (this._el.propertiesToggleBtn) this._el.propertiesToggleBtn.classList.add("toolbar-btn--active")
    }

    this._storedTypewriterLayout = null
    this._persist()
  }

  enterAiReviewFocus() {
    if (this._aiReviewFocusMode) return

    const tagSidebar = document.getElementById("tag-sidebar")
    this._storedAiReviewLayout = {
      previewVisible: this._previewVisible,
      previewPaneFlex: this._el.previewPane.style.flex,
      editorPaneHidden: this._el.editorPane.classList.contains("hidden"),
      resizeHandleHidden: this._el.previewResizeHandle.classList.contains("hidden"),
      tagSidebarHidden: tagSidebar?.classList.contains("hidden") || false
    }

    this._aiReviewFocusMode = true
    this._previewVisible = true
    this._el.previewPane.classList.remove("hidden")
    this._el.previewPane.style.flex = "1 1 auto"
    this._el.editorPane.classList.add("hidden")
    this._el.previewResizeHandle.classList.add("hidden")
    tagSidebar?.classList.add("hidden")
  }

  exitAiReviewFocus() {
    if (!this._aiReviewFocusMode) return

    const tagSidebar = document.getElementById("tag-sidebar")
    const stored = this._storedAiReviewLayout || {}

    this._aiReviewFocusMode = false
    this._storedAiReviewLayout = null

    this._el.editorPane.classList.toggle("hidden", !!stored.editorPaneHidden)
    this._el.previewResizeHandle.classList.toggle("hidden", !!stored.resizeHandleHidden)
    tagSidebar?.classList.toggle("hidden", !!stored.tagSidebarHidden)

    this._previewVisible = stored.previewVisible !== false
    if (this._previewVisible) {
      this._el.previewPane.classList.remove("hidden")
      this._el.previewToggleBtn.classList.add("toolbar-btn--active")
      this._el.previewPane.style.flex = stored.previewPaneFlex || ""
      if (!stored.previewPaneFlex) this._applyPreviewWidth(this._previewWidthRatio || 0.5)
    } else {
      this._el.previewPane.classList.add("hidden")
      this._el.previewToggleBtn.classList.remove("toolbar-btn--active")
      this._el.previewPane.style.flex = stored.previewPaneFlex || ""
      this._el.editorPane.style.flex = "1 1 auto"
    }
  }

  updateStorageKey(key) {
    this._storageKey = key
  }

  // ── Private ──────────────────────────────────────────────

  _applyPreviewWidth(ratio) {
    if (!this._previewVisible) return
    const bounded = Math.min(Math.max(ratio, 0.25), 0.75)
    this._previewWidthRatio = bounded
    this._el.previewPane.style.flex = `0 0 ${bounded * 100}%`
    this._el.editorPane.style.flex = "1 1 auto"
    this._syncEditorWidthMode()
  }

  _applyContextHeight(height) {
    const bounded = Math.min(Math.max(height, 140), window.innerHeight * 0.72)
    this._contextHeight = bounded
    if (this._el.contextMode.value === "hidden") {
      this._el.contextPanel.style.flex = "0 0 auto"
      return
    }
    this._el.contextPanel.style.flex = `0 0 ${bounded}px`
  }

  _syncEditorWidthMode() {
    this._el.editorPane.classList.toggle("editor-pane--full-width", !this._previewVisible && !this._aiReviewFocusMode)
  }

  _persist() {
    const payload = {
      previewWidthRatio: this._previewWidthRatio,
      contextHeight: this._contextHeight,
      contextMode: this._el.contextMode.value,
      previewVisible: this._previewVisible,
      propertiesVisible: this._propertiesVisible
    }
    window.localStorage?.setItem(this._storageKey, JSON.stringify(payload))
  }

  _readState() {
    try {
      return JSON.parse(window.localStorage?.getItem(this._storageKey) || "{}")
    } catch {
      return {}
    }
  }
}
