import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["banner"]

  connect() {
    this._online = true
    this._timer = setInterval(() => this._check(), 5000)
    this._check()
  }

  disconnect() {
    clearInterval(this._timer)
  }

  async _check() {
    try {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 3000)
      const response = await fetch("/up", { method: "HEAD", signal: controller.signal })
      clearTimeout(timeout)

      if (response.ok && !this._online) {
        this._online = true
        this._setOffline(false)
        this.dispatch("online", { bubbles: true })
      }
    } catch {
      if (this._online) {
        this._online = false
        this._setOffline(true)
        this.dispatch("offline", { bubbles: true })
      }
    }
  }

  _setOffline(offline) {
    if (this.hasBannerTarget) {
      this.bannerTarget.classList.toggle("hidden", !offline)
    }
  }
}
