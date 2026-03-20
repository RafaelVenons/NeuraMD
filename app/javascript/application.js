// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

if (window.Turbo?.StreamActions) {
  window.Turbo.StreamActions.dispatch_event = function() {
    const name = this.getAttribute("name")
    if (!name) return

    const detail = this.getAttribute("detail")
    const targetId = this.getAttribute("target")
    const target = targetId ? document.getElementById(targetId) : document.documentElement
    if (!target) return

    let payload = detail

    try {
      payload = detail ? JSON.parse(detail) : null
    } catch (_) {
    }

    target.dispatchEvent(new CustomEvent(name, {
      bubbles: true,
      detail: payload
    }))
  }
}
