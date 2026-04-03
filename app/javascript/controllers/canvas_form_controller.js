import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name"]
  static values = { createUrl: String }

  async create() {
    const name = this.nameTarget.value.trim()
    if (!name) {
      this.nameTarget.focus()
      return
    }

    const response = await fetch(this.createUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this._csrfToken(),
        Accept: "application/json"
      },
      body: JSON.stringify({ canvas_document: { name } })
    })

    if (response.ok) {
      const data = await response.json()
      window.location.href = `/canvas/${data.id}`
    }
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
