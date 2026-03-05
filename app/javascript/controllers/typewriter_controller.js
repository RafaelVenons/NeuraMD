import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor"]

  connect() {
    this._enabled = localStorage.getItem("neuramd:typewriter") === "true"
    if (this._enabled) this._apply()
  }

  toggle() {
    this._enabled = !this._enabled
    localStorage.setItem("neuramd:typewriter", String(this._enabled))
    if (this._enabled) {
      this._apply()
    } else {
      this._remove()
    }

    // Update toolbar button state
    const btn = document.querySelector("[data-editor-target='typewriterBtn']")
    btn?.classList.toggle("toolbar-btn--active", this._enabled)
  }

  _apply() {
    const host = document.getElementById("codemirror-host")
    if (!host) return
    host.classList.add("typewriter-mode")

    // Listen for changes to keep cursor centered
    this._scrollHandler = () => {} // scroll is handled by CSS
  }

  _remove() {
    const host = document.getElementById("codemirror-host")
    if (!host) return
    host.classList.remove("typewriter-mode")
  }
}
