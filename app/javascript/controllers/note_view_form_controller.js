import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "filter", "displayType", "columnCheck"]
  static values = { createUrl: String, propertyDefs: Array }

  async create() {
    const name = this.nameTarget.value.trim()
    if (!name) {
      this.nameTarget.focus()
      return
    }

    const columns = ["title"]
    this.columnCheckTargets.forEach(cb => {
      if (cb.checked) columns.push(cb.value)
    })

    const body = {
      note_view: {
        name,
        filter_query: this.filterTarget.value.trim(),
        display_type: this.displayTypeTarget.value,
        columns,
        sort_config: JSON.stringify({field: "updated_at", direction: "desc"})
      }
    }

    const response = await fetch(this.createUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this._csrfToken(),
        Accept: "application/json"
      },
      body: JSON.stringify(body)
    })

    if (response.ok) {
      const data = await response.json()
      window.location.href = `/views/${data.id}`
    }
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
