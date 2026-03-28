import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor"]

  connect() {
    this._keyHandler = this._handleKey.bind(this)
    document.addEventListener("keydown", this._keyHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
  }

  bold()       { this._wrap("**", "**") }
  italic()     { this._wrap("_", "_") }
  inlineCode() { this._wrap("`", "`") }
  strikethrough() { this._wrap("~~", "~~") }
  highlight()  { this._wrap("==", "==") }

  link() {
    const editor = this._getEditor()
    if (!editor) return
    const selection = editor.getSelection()
    if (selection) {
      editor.replaceSelection(`[${selection}](url)`)
    } else {
      editor.replaceSelection("[texto](url)")
    }
    editor.focus()
  }

  heading1()  { this._insertLinePrefix("# ") }
  heading2()  { this._insertLinePrefix("## ") }
  heading3()  { this._insertLinePrefix("### ") }
  bulletList() { this._insertLinePrefix("- ") }
  numberList() { this._insertLinePrefix("1. ") }
  blockquote() { this._insertLinePrefix("> ") }

  codeBlock() {
    const editor = this._getEditor()
    if (!editor) return
    const selection = editor.getSelection()
    if (selection) {
      editor.replaceSelection(`\`\`\`\n${selection}\n\`\`\``)
    } else {
      editor.replaceSelection("```\n\n```")
    }
    editor.focus()
  }

  _handleKey(e) {
    if (e.isComposing || e.keyCode === 229 || this._getEditor()?.isComposing()) return
    const ctrl = e.ctrlKey || e.metaKey
    if (!ctrl) return

    // Only handle if editor has focus
    const editor = this._getEditor()
    if (!editor) return

    if (e.shiftKey) {
      switch (e.key) {
        case "S": e.preventDefault(); this.strikethrough(); return
        case "H": e.preventDefault(); this.highlight(); return
      }
    }

    switch (e.key) {
      case "b": e.preventDefault(); this.bold(); break
      case "i": e.preventDefault(); this.italic(); break
      case "`": e.preventDefault(); this.inlineCode(); break
      case "k": e.preventDefault(); this.link(); break
    }
  }

  _wrap(before, after) {
    const editor = this._getEditor()
    if (!editor) return
    editor.wrapSelection(before, after)
  }

  _insertLinePrefix(prefix) {
    const editor = this._getEditor()
    if (!editor) return
    const view = editor.view
    if (!view) return
    const pos = view.state.selection.main.head
    const line = view.state.doc.lineAt(pos)
    view.dispatch({
      changes: { from: line.from, to: line.from, insert: prefix },
      selection: { anchor: line.from + prefix.length }
    })
    view.focus()
  }

  _getEditor() {
    const app = this.application
    const el = document.querySelector("[data-controller~='codemirror']")
    if (!el) return null
    return app.getControllerForElementAndIdentifier(el, "codemirror")
  }
}
