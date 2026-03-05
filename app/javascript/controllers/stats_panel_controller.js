import { Controller } from "@hotwired/stimulus"
import { wordCount, lineCount } from "lib/stats_utils"

export default class extends Controller {
  static targets = ["words", "lines", "position", "bar"]

  connect() {
    // Listen for CodeMirror events from parent
    this.element.addEventListener("codemirror:change", this._onContentChange.bind(this))
    this.element.addEventListener("codemirror:selectionchange", this._onSelectionChange.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("codemirror:change", this._onContentChange.bind(this))
    this.element.removeEventListener("codemirror:selectionchange", this._onSelectionChange.bind(this))
  }

  _onContentChange(e) {
    const value = e.detail.value || ""
    if (this.hasWordsTarget) {
      this.wordsTarget.textContent = `${wordCount(value)} palavras`
    }
    if (this.hasLinesTarget) {
      this.linesTarget.textContent = `${lineCount(value)} linhas`
    }
  }

  _onSelectionChange(e) {
    const { line, col } = e.detail
    if (this.hasPositionTarget) {
      this.positionTarget.textContent = `L${line}, C${col}`
    }
  }
}
