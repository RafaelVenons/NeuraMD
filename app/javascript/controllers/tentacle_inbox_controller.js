import { Controller } from "@hotwired/stimulus"

const POLL_INTERVAL_MS = 5000

export default class extends Controller {
  static targets = ["list", "status", "empty"]
  static values = { url: String, deliverUrl: String, csrf: String }

  connect() {
    this.messages = []
    this.pendingCount = 0
    this.timer = null
    this.load()
    this.timer = setInterval(() => this.load(), POLL_INTERVAL_MS)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  async load() {
    try {
      const res = await fetch(this.urlValue, {
        credentials: "same-origin",
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) throw new Error(`load failed (${res.status})`)
      const body = await res.json()
      this.messages = Array.isArray(body.messages) ? body.messages : []
      this.pendingCount = Number(body.pending_count) || 0
      this.render()
    } catch (err) {
      console.error(err)
      this.setStatus("erro")
    }
  }

  async deliverAll(event) {
    event?.preventDefault()
    try {
      const res = await fetch(this.deliverUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        }
      })
      if (!res.ok) throw new Error(`deliver failed (${res.status})`)
      await this.load()
    } catch (err) {
      console.error(err)
      this.setStatus("erro")
    }
  }

  render() {
    const listEl = this.listTarget
    listEl.replaceChildren()

    if (this.hasEmptyTarget) this.emptyTarget.hidden = this.messages.length > 0

    this.messages.forEach((msg) => {
      const li = document.createElement("li")
      li.className = "nm-tentacle__inbox-item" + (msg.delivered ? "" : " nm-tentacle__inbox-item--pending")

      const header = document.createElement("div")
      header.className = "nm-tentacle__inbox-from"
      const when = msg.created_at ? this.formatTime(msg.created_at) : ""
      header.textContent = `${msg.from_title || msg.from_slug} · ${when}`

      const body = document.createElement("div")
      body.className = "nm-tentacle__inbox-content"
      body.textContent = msg.content

      li.append(header, body)
      listEl.append(li)
    })

    this.setStatus(this.pendingCount > 0 ? `${this.pendingCount} pendente${this.pendingCount === 1 ? "" : "s"}` : `${this.messages.length}`)
  }

  formatTime(iso) {
    try {
      const d = new Date(iso)
      return d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })
    } catch {
      return iso
    }
  }

  setStatus(label) {
    if (this.hasStatusTarget) this.statusTarget.textContent = label
  }
}
