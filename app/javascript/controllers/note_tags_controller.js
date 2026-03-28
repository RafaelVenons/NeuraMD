import { Controller } from "@hotwired/stimulus"

// Manages note-level tag chips in the editor toolbar.
// Shows colored chips for tags attached to the current note.
// Dropdown to add tags, × button to remove.
export default class extends Controller {
  static values  = { noteId: String, initialTags: { type: Array, default: [] } }
  static targets = ["chipContainer", "addButton", "dropdown"]

  connect() {
    this._tags = [...this.initialTagsValue]
    this._allTags = []
    this._dropdownOpen = false

    this._onDocClick = (e) => {
      if (!this._dropdownOpen) return
      if (this.dropdownTarget.contains(e.target)) return
      if (this.addButtonTarget.contains(e.target)) return
      this._closeDropdown()
    }
    document.addEventListener("click", this._onDocClick)

    this._renderChips()
    this._loadAllTags()
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
  }

  hydrateNoteContext(payload) {
    this.noteIdValue = payload.note?.id || this.noteIdValue
    this._tags = payload.note_tags || []
    this._renderChips()
    this._closeDropdown()
  }

  toggleDropdown() {
    if (this._dropdownOpen) {
      this._closeDropdown()
    } else {
      this._openDropdown()
    }
  }

  async _loadAllTags() {
    try {
      const res = await fetch("/tags", { headers: { Accept: "application/json" } })
      if (!res.ok) return
      this._allTags = await res.json()
    } catch (_) {}
  }

  _renderChips() {
    if (!this.hasChipContainerTarget) return
    this.chipContainerTarget.innerHTML = ""

    for (const tag of this._tags) {
      const chip = document.createElement("span")
      chip.className = "note-tag-chip"
      chip.style.cssText = `background: ${tag.color_hex || "#6b7280"}20; color: ${tag.color_hex || "#6b7280"}; border: 1px solid ${tag.color_hex || "#6b7280"}40;`
      chip.dataset.tagId = tag.id
      chip.innerHTML = `
        <span class="note-tag-chip-label">${this._escapeHtml(tag.name)}</span>
        <button type="button" class="note-tag-chip-remove" title="Remover tag">&times;</button>
      `
      chip.querySelector(".note-tag-chip-remove").addEventListener("click", (e) => {
        e.stopPropagation()
        this._removeTag(tag.id)
      })
      this.chipContainerTarget.appendChild(chip)
    }
  }

  _openDropdown() {
    if (!this.hasDropdownTarget) return
    this._dropdownOpen = true

    const attachedIds = new Set(this._tags.map(t => t.id))
    const available = this._allTags.filter(t =>
      !attachedIds.has(t.id) && (t.tag_scope === "note" || t.tag_scope === "both")
    )

    this.dropdownTarget.innerHTML = ""

    if (available.length === 0) {
      const empty = document.createElement("p")
      empty.className = "px-3 py-2 text-xs"
      empty.style.color = "var(--theme-text-faint)"
      empty.textContent = "Nenhuma tag disponível"
      this.dropdownTarget.appendChild(empty)
    } else {
      for (const tag of available) {
        const btn = document.createElement("button")
        btn.type = "button"
        btn.className = "note-tag-option"
        btn.innerHTML = `
          <span class="note-tag-option-dot" style="background: ${tag.color_hex || "#6b7280"};"></span>
          ${this._escapeHtml(tag.name)}
        `
        btn.addEventListener("click", () => this._addTag(tag))
        this.dropdownTarget.appendChild(btn)
      }
    }

    this.dropdownTarget.classList.remove("hidden")
  }

  _closeDropdown() {
    if (!this.hasDropdownTarget) return
    this._dropdownOpen = false
    this.dropdownTarget.classList.add("hidden")
  }

  async _addTag(tag) {
    this._closeDropdown()
    this._tags.push({ id: tag.id, name: tag.name, color_hex: tag.color_hex })
    this._renderChips()

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch("/note_tags", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({ note_id: this.noteIdValue, tag_id: tag.id })
      })
    } catch (_) {}
  }

  async _removeTag(tagId) {
    this._tags = this._tags.filter(t => t.id !== tagId)
    this._renderChips()

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch("/note_tags", {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({ note_id: this.noteIdValue, tag_id: tagId })
      })
    } catch (_) {}
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
