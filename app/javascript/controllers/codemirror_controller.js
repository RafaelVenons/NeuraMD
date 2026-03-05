import { Controller } from "@hotwired/stimulus"
import { EditorState, Compartment } from "@codemirror/state"
import {
  EditorView, keymap, lineNumbers, drawSelection,
  dropCursor, rectangularSelection, crosshairCursor, highlightActiveLine,
  highlightActiveLineGutter, scrollPastEnd
} from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { languages } from "@codemirror/language-data"
import { searchKeymap } from "@codemirror/search"
import { oneDark } from "@codemirror/theme-one-dark"

export default class extends Controller {
  static targets = ["host"]
  static values = { initialValue: String }

  connect() {
    this._themeCompartment = new Compartment()
    this._lineNumbersCompartment = new Compartment()
    this._readOnlyCompartment = new Compartment()

    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        this._dispatchChange()
      }
      if (update.selectionSet) {
        this._dispatchSelectionChange()
      }
    })

    const scrollListener = EditorView.domEventHandlers({
      scroll: () => { this._dispatchScroll() }
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
        scrollPastEnd(),
        this._lineNumbersCompartment.of(lineNumbers()),
        this._themeCompartment.of(oneDark),
        this._readOnlyCompartment.of(EditorState.readOnly.of(false)),
        keymap.of([
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
          indentWithTab,
        ]),
        markdown({ base: markdownLanguage, codeLanguages: languages }),
        updateListener,
        scrollListener,
        EditorView.lineWrapping,
      ]
    })

    this._view = new EditorView({
      state,
      parent: this.hostTarget
    })

    // Notify other controllers editor is ready
    this.dispatch("ready", { detail: { editor: this } })
  }

  disconnect() {
    this._view?.destroy()
    this._view = null
  }

  // Public API
  getValue() {
    return this._view?.state.doc.toString() || ""
  }

  setValue(value) {
    if (!this._view) return
    this._view.dispatch({
      changes: { from: 0, to: this._view.state.doc.length, insert: value }
    })
  }

  getSelection() {
    if (!this._view) return ""
    const { from, to } = this._view.state.selection.main
    return this._view.state.doc.sliceString(from, to)
  }

  replaceSelection(text) {
    if (!this._view) return
    this._view.dispatch(this._view.state.replaceSelection(text))
    this._view.focus()
  }

  focus() {
    this._view?.focus()
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
      // Select placeholder
      const { from } = this._view.state.selection.main
      const start = from - placeholder.length - after.length
      const end = start + placeholder.length
      this._view.dispatch({ selection: { anchor: start, head: end } })
    }
  }

  get view() { return this._view }

  // Private
  _dispatchChange() {
    this.dispatch("change", {
      detail: { value: this.getValue() },
      bubbles: true
    })
  }

  _dispatchSelectionChange() {
    const pos = this.getCursorPosition()
    this.dispatch("selectionchange", {
      detail: { ...pos, value: this.getValue() },
      bubbles: true
    })
  }

  _dispatchScroll() {
    this.dispatch("scroll", {
      detail: { ratio: this.getScrollRatio() },
      bubbles: true
    })
  }
}
