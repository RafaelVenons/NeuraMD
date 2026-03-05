import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "findInput", "replaceInput", "caseSensitive", "useRegex", "matchCount"]

  connect() {
    this._matches = []
    this._currentMatch = -1
    this._editorController = null
  }

  open() {
    this.dialogTarget.classList.remove("hidden")
    this.findInputTarget.focus()
    this.findInputTarget.select()
  }

  close() {
    this.dialogTarget.classList.add("hidden")
    this._getEditor()?.focus()
  }

  handleFindKey(e) {
    if (e.key === "Enter") {
      e.shiftKey ? this.previous() : this.next()
    }
    if (e.key === "Escape") this.close()
  }

  search() {
    const term = this.findInputTarget.value
    if (!term) {
      this.matchCountTarget.textContent = "—"
      return
    }

    const editor = this._getEditor()
    if (!editor) return

    const content = editor.getValue()
    const flags = this.caseSensitiveTarget.checked ? "g" : "gi"
    let regex

    try {
      regex = this.useRegexTarget.checked
        ? new RegExp(term, flags)
        : new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), flags)
    } catch {
      this.matchCountTarget.textContent = "Regex inválida"
      return
    }

    this._matches = []
    let match
    while ((match = regex.exec(content)) !== null) {
      this._matches.push({ from: match.index, to: match.index + match[0].length, text: match[0] })
      if (this._matches.length > 1000) break
    }

    this._currentMatch = this._matches.length > 0 ? 0 : -1
    this.matchCountTarget.textContent = `${this._matches.length} resultados`
    this._highlightCurrent()
  }

  next() {
    if (!this._matches.length) { this.search(); return }
    this._currentMatch = (this._currentMatch + 1) % this._matches.length
    this._highlightCurrent()
  }

  previous() {
    if (!this._matches.length) { this.search(); return }
    this._currentMatch = (this._currentMatch - 1 + this._matches.length) % this._matches.length
    this._highlightCurrent()
  }

  replaceCurrent() {
    if (this._currentMatch < 0 || !this._matches.length) return
    const editor = this._getEditor()
    if (!editor) return
    const match = this._matches[this._currentMatch]
    const replaceWith = this.replaceInputTarget.value

    // Use CodeMirror dispatch for precise replacement
    const view = editor.view
    if (view) {
      view.dispatch({ changes: { from: match.from, to: match.to, insert: replaceWith } })
      this.search()
    }
  }

  replaceAll() {
    const editor = this._getEditor()
    if (!editor || !this._matches.length) return
    const replaceWith = this.replaceInputTarget.value
    const view = editor.view
    if (!view) return

    const changes = this._matches.map(m => ({ from: m.from, to: m.to, insert: replaceWith }))
    view.dispatch({ changes })
    this.search()
  }

  _highlightCurrent() {
    if (this._currentMatch < 0) return
    const editor = this._getEditor()
    if (!editor) return
    const match = this._matches[this._currentMatch]
    const view = editor.view
    if (view) {
      view.dispatch({
        selection: { anchor: match.from, head: match.to },
        scrollIntoView: true
      })
    }
    const total = this._matches.length
    this.matchCountTarget.textContent = `${this._currentMatch + 1}/${total}`
  }

  _getEditor() {
    const app = this.application
    // Find codemirror controller in the page
    const el = document.querySelector("[data-controller~='codemirror']")
    if (!el) return null
    return app.getControllerForElementAndIdentifier(el, "codemirror")
  }
}
