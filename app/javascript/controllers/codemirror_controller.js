import { Controller } from "@hotwired/stimulus"
import { EditorState, Compartment } from "@codemirror/state"
import {
  EditorView, keymap, lineNumbers, drawSelection,
  dropCursor, rectangularSelection, crosshairCursor, highlightActiveLine,
  highlightActiveLineGutter
} from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { languages } from "@codemirror/language-data"
import { searchKeymap } from "@codemirror/search"
import { oneDark } from "@codemirror/theme-one-dark"
import { aiDiffExtension, clearAiDiffEffect, setAiDiffEffect } from "editor/ai_diff_extension"
import {
  createTypewriterExtension,
  getTypewriterSyncData,
  isTypewriterEnabled,
  maintainTypewriterScroll,
  setTypewriterSelecting,
  toggleTypewriter
} from "editor/typewriter_extension"
import { wikilinkBrokenExtension } from "editor/wikilink_broken_extension"

export default class extends Controller {
  static targets = ["host"]
  static values = { initialValue: String }

  connect() {
    this._themeCompartment = new Compartment()
    this._aiDiffCompartment = new Compartment()
    this._lineNumbersCompartment = new Compartment()
    this._readOnlyCompartment = new Compartment()
    this._suppressChangeDispatch = false
    this._isComposing = false
    this._aiStageActive = false
    this._aiDiffVisible = false

    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged && !this._suppressChangeDispatch) {
        if (!this._aiStageActive && this._aiDiffVisible) {
          this.clearAiDiff()
        }
        this._dispatchChange()
      }
      this._suppressChangeDispatch = false
      if (update.selectionSet) {
        this._dispatchSelectionChange()
      }
    })

    const scrollListener = EditorView.domEventHandlers({
      scroll: () => { this._dispatchScroll() },
      compositionstart: () => { this._setComposing(true) },
      compositionend: () => {
        // Let the committed IME text land before clearing the composition flag.
        setTimeout(() => { this._setComposing(false) }, 0)
      }
    })

    const state = EditorState.create({
      doc: this.initialValueValue || "",
      extensions: [
        history(),
        drawSelection(),
        dropCursor(),
        rectangularSelection(),
        crosshairCursor(),
        highlightActiveLine(),
        highlightActiveLineGutter(),
        this._lineNumbersCompartment.of(lineNumbers()),
        this._themeCompartment.of(oneDark),
        this._aiDiffCompartment.of(aiDiffExtension()),
        this._readOnlyCompartment.of(EditorState.readOnly.of(false)),
        ...createTypewriterExtension(localStorage.getItem("neuramd:typewriter") === "true"),
        keymap.of([
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
          indentWithTab,
        ]),
        markdown({ base: markdownLanguage, codeLanguages: languages }),
        wikilinkBrokenExtension(),
        updateListener,
        scrollListener,
        EditorView.lineWrapping,
      ]
    })

    this._view = new EditorView({
      state,
      parent: this.hostTarget
    })

    // Listen for wiki-link insertion requests from wikilink_controller
    this.element.addEventListener("wikilink:insert", (e) => {
      this._insertWikilink(e.detail.markup, e.detail.insertStart)
    })
    this._onAiStageChange = (event) => {
      this._aiStageActive = !!event.detail?.active
      if (!this._aiStageActive && this._aiDiffVisible) this.clearAiDiff()
    }
    this.element.addEventListener("ai-review:stagechange", this._onAiStageChange)
    this._setupMouseTracking()

    // Notify other controllers editor is ready (bubbles to editor_controller)
    this.dispatch("ready", { detail: { editor: this } })

    // Trigger initial preview render. codemirror:change only fires on mutations,
    // not on initial load, so the preview would stay blank without this.
    // setTimeout(0) defers the dispatch past the current synchronous connect()
    // cycle so that preview_controller (later in DOM order) has already connected
    // and registered its listeners before the event fires.
    if (this.initialValueValue) setTimeout(() => this._dispatchChange(), 0)
  }

  disconnect() {
    this.element.removeEventListener("ai-review:stagechange", this._onAiStageChange)
    if (this._view?.scrollDOM && this._mouseDownHandler) {
      this._view.scrollDOM.removeEventListener("mousedown", this._mouseDownHandler)
    }
    if (this._mouseUpHandler) {
      document.removeEventListener("mouseup", this._mouseUpHandler)
    }
    this._view?.destroy()
    this._view = null
  }

  // Public API
  getValue() {
    return this._view?.state.doc.toString() || ""
  }

  setValue(value, { silent = false } = {}) {
    if (!this._view) return
    this._suppressChangeDispatch = silent
    this._view.dispatch({
      changes: { from: 0, to: this._view.state.doc.length, insert: value }
    })
  }

  getSelection() {
    if (!this._view) return ""
    const { from, to } = this._view.state.selection.main
    return this._view.state.doc.sliceString(from, to)
  }

  getSelectionRange() {
    if (!this._view) return { from: 0, to: 0 }
    const { from, to } = this._view.state.selection.main
    return { from, to }
  }

  replaceSelection(text) {
    if (!this._view) return
    this._view.dispatch(this._view.state.replaceSelection(text))
    this._view.focus()
  }

  replaceRange(from, to, text, { selectionAnchor = null, selectionHead = null } = {}) {
    if (!this._view) return
    const transaction = {
      changes: { from, to, insert: text }
    }

    if (selectionAnchor != null || selectionHead != null) {
      transaction.selection = {
        anchor: selectionAnchor ?? selectionHead ?? from,
        head: selectionHead ?? selectionAnchor ?? from
      }
    }

    this._view.dispatch(transaction)
    this._view.focus()
  }

  focus() {
    this._view?.focus()
  }

  notifyChange() {
    this._dispatchChange()
  }

  showAiDiff({ originalText = "", aiSuggestedText = "" } = {}) {
    if (!this._view) return
    this._aiDiffVisible = true
    this._view.dispatch({
      effects: setAiDiffEffect({
        originalText,
        currentText: this.getValue(),
        aiSuggestedText
      })
    })
  }

  clearAiDiff() {
    if (!this._view) return
    this._aiDiffVisible = false
    this._view.dispatch({
      effects: clearAiDiffEffect()
    })
  }

  getScrollRatio() {
    if (!this._view) return 0
    const el = this._view.scrollDOM
    const max = el.scrollHeight - el.clientHeight
    return max > 0 ? el.scrollTop / max : 0
  }

  setScrollRatio(ratio) {
    if (!this._view) return
    const el = this._view.scrollDOM
    const max = el.scrollHeight - el.clientHeight
    el.scrollTop = max * ratio
  }

  getCursorPosition() {
    if (!this._view) return { line: 1, col: 1 }
    const pos = this._view.state.selection.main.head
    const line = this._view.state.doc.lineAt(pos)
    return { line: line.number, col: pos - line.from + 1 }
  }

  getCursorClientRect() {
    if (!this._view) return null
    const head = this._view.state.selection.main.head
    const coords = this._view.coordsAtPos(head)
    if (!coords) return null

    return {
      left: coords.left,
      top: coords.top,
      right: coords.right,
      bottom: coords.bottom
    }
  }

  setTypewriterMode(enabled) {
    if (!this._view) return
    toggleTypewriter(this._view, enabled)
    this._dispatchSelectionChange()
  }

  toggleTypewriterMode() {
    const nextState = !this.isTypewriterMode()
    this.setTypewriterMode(nextState)
    return nextState
  }

  isTypewriterMode() {
    return isTypewriterEnabled(this._view)
  }

  getTypewriterSyncData() {
    return getTypewriterSyncData(this._view)
  }

  maintainTypewriterScroll() {
    if (!this._view || !this.isTypewriterMode()) return
    maintainTypewriterScroll(this._view)
  }

  jumpToLine(lineNum) {
    if (!this._view) return
    const doc = this._view.state.doc
    const clampedLine = Math.max(1, Math.min(lineNum, doc.lines))
    const line = doc.line(clampedLine)
    this._view.dispatch({
      selection: { anchor: line.from },
      scrollIntoView: true
    })
    this._view.focus()
  }

  wrapSelection(before, after) {
    const selection = this.getSelection()
    if (selection) {
      this.replaceSelection(`${before}${selection}${after}`)
    } else {
      const placeholder = before.replace(/\*|_|`/g, "").trim() || "texto"
      this.replaceSelection(`${before}${placeholder}${after}`)
      const { from } = this._view.state.selection.main
      const start = from - placeholder.length - after.length
      const end = start + placeholder.length
      this._view.dispatch({ selection: { anchor: start, head: end } })
    }
  }

  get view() { return this._view }

  isComposing() {
    return this._isComposing || this._view?.composing || false
  }

  // Replace text from insertStart to current cursor with the wiki-link markup.
  _insertWikilink(markup, insertStart) {
    if (!this._view) return
    const cursorPos = this._view.state.selection.main.head
    this._view.dispatch({
      changes: { from: insertStart, to: cursorPos, insert: markup },
      selection: { anchor: insertStart + markup.length }
    })
    this._view.focus()
  }

  // Private
  _dispatchChange() {
    const cursorPos = this._view?.state.selection.main.head ?? 0
    this.dispatch("change", {
      detail: { value: this.getValue(), cursorPos, cm: this, isComposing: this.isComposing() },
      bubbles: true
    })
  }

  _dispatchSelectionChange() {
    const pos       = this.getCursorPosition()
    const cursorPos = this._view?.state.selection.main.head ?? 0
    const typewriter = this.isTypewriterMode() ? this.getTypewriterSyncData() : null
    this.dispatch("selectionchange", {
      detail: {
        ...pos,
        cursorPos,
        value: this.getValue(),
        isComposing: this.isComposing(),
        typewriterMode: !!typewriter,
        typewriter
      },
      bubbles: true
    })
  }

  _dispatchScroll() {
    this.dispatch("scroll", {
      detail: { ratio: this.getScrollRatio() },
      bubbles: true
    })
  }

  _setComposing(isComposing) {
    this._isComposing = isComposing
    this.dispatch("compositionchange", {
      detail: { isComposing: this.isComposing() },
      bubbles: true
    })
  }

  _setupMouseTracking() {
    if (!this._view) return

    const onMouseDown = (event) => {
      if (event.button !== 0) return
      setTypewriterSelecting(this._view, true)
    }

    const onMouseUp = () => {
      if (!this._view) return
      setTypewriterSelecting(this._view, false)
      setTimeout(() => this._dispatchSelectionChange(), 0)
    }

    this._mouseDownHandler = onMouseDown
    this._mouseUpHandler = onMouseUp
    this._view.scrollDOM.addEventListener("mousedown", onMouseDown)
    document.addEventListener("mouseup", onMouseUp)
  }
}
