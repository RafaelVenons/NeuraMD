import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.poll()
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  poll() {
    this.timer = setTimeout(async () => {
      try {
        const resp = await fetch(this.urlValue, { headers: { Accept: "text/html" } })
        if (!resp.ok) return this.poll()
        const html = await resp.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, "text/html")
        const newStatus = doc.getElementById("file_import_status")
        if (newStatus) {
          document.getElementById("file_import_status").innerHTML = newStatus.innerHTML
        }
        // Stop polling if terminal state
        const badge = newStatus?.querySelector(".fi-status__badge")?.textContent?.trim()?.toLowerCase()
        if (badge === "completed" || badge === "failed") {
          // Reload page to get final state with action links
          window.location.reload()
          return
        }
      } catch (_) { /* ignore fetch errors, retry */ }
      this.poll()
    }, this.intervalValue)
  }
}
