import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "lineInput"]

  open() {
    this.dialogTarget.classList.remove("hidden")
    this.lineInputTarget.focus()
    this.lineInputTarget.select()
  }

  close() {
    this.dialogTarget.classList.add("hidden")
    this._getEditor()?.focus()
  }

  handleKey(e) {
    if (e.key === "Enter") this.jump()
    if (e.key === "Escape") this.close()
  }

  jump() {
    const lineNum = parseInt(this.lineInputTarget.value, 10)
    if (!lineNum || lineNum < 1) return
    this._getEditor()?.jumpToLine(lineNum)
    this.close()
  }

  _getEditor() {
    const app = this.application
    const el = document.querySelector("[data-controller~='codemirror']")
    if (!el) return null
    return app.getControllerForElementAndIdentifier(el, "codemirror")
  }
}
