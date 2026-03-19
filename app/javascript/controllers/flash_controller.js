import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 2500 } }

  connect() {
    this.timeoutId = window.setTimeout(() => {
      this.element.classList.add("nm-app-flash__message--closing")
      window.setTimeout(() => this.element.remove(), 220)
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeoutId) window.clearTimeout(this.timeoutId)
  }
}
