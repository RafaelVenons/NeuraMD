import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor"]

  connect() {
    this._enabled = localStorage.getItem("neuramd:typewriter") === "true"
    this._apply()
    setTimeout(() => this._syncCodemirror(), 0)
    setTimeout(() => this.dispatch("toggled", { detail: { enabled: this._enabled } }), 0)
  }

  toggle() {
    this._enabled = !this._enabled
    localStorage.setItem("neuramd:typewriter", String(this._enabled))
    this._apply()
    this._syncCodemirror()
    this.dispatch("toggled", { detail: { enabled: this._enabled } })
  }

  _apply() {
    document.body.classList.toggle("typewriter-mode", this._enabled)
    const btn = document.querySelector("[data-editor-target='typewriterBtn']")
    btn?.classList.toggle("toolbar-btn--active", this._enabled)
    btn?.setAttribute("aria-pressed", String(this._enabled))
  }

  _syncCodemirror() {
    const controller = this._codemirrorController()
    controller?.setTypewriterMode(this._enabled)
  }

  _codemirrorController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "codemirror")
  }
}
