import { Controller } from "@hotwired/stimulus"

// Manages note-level tags via a compact dropdown in the toolbar.
// Shows a tag icon + count badge. Dropdown lists current tags (removable)
// and available tags (addable).
export default class extends Controller {
  static values  = { noteId: String, initialTags: { type: Array, default: [] } }
  static targets = ["toggleButton", "badge", "dropdown"]

  connect() {
    this._tags = [...this.initialTagsValue]
    this._allTags = []
    this._dropdownOpen = false

    this._onDocClick = (e) => {
      if (!this._dropdownOpen) return
      if (this.dropdownTarget.contains(e.target)) return
      if (this.toggleButtonTarget.contains(e.target)) return
      this._closeDropdown()
    }
    document.addEventListener("click", this._onDocClick)

    this._renderBadge()
    this._loadAllTags()
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
  }

  hydrateNoteContext(payload) {
    this.noteIdValue = payload.note?.id || this.noteIdValue
    this._tags = payload.note_tags || []
    this._renderBadge()
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

  _renderBadge() {
    if (!this.hasBadgeTarget) return
    const count = this._tags.length
    this.badgeTarget.textContent = count > 0 ? count : ""
    this.badgeTarget.classList.toggle("hidden", count === 0)
  }

  _openDropdown() {
    if (!this.hasDropdownTarget) return
    this._dropdownOpen = true

    const attachedIds = new Set(this._tags.map(t => t.id))
    const available = this._allTags.filter(t =>
      !attachedIds.has(t.id) && (t.tag_scope === "note" || t.tag_scope === "both")
    )

    this.dropdownTarget.innerHTML = ""

    // Current tags section
    if (this._tags.length > 0) {
      const header = document.createElement("p")
      header.className = "px-3 pt-2 pb-1 text-[10px] uppercase tracking-wider font-semibold"
      header.style.color = "var(--theme-text-faint)"
      header.textContent = "Tags da nota"
      this.dropdownTarget.appendChild(header)

      for (const tag of this._tags) {
        const row = document.createElement("div")
        row.className = "note-tag-dropdown-item"
        row.innerHTML = `
          <span class="note-tag-option-dot" style="background: ${tag.color_hex || "#6b7280"};"></span>
          <span class="flex-1 text-sm truncate">${this._escapeHtml(tag.name)}</span>
          <button type="button" class="note-tag-chip-remove" title="Remover tag">&times;</button>
        `
        row.querySelector(".note-tag-chip-remove").addEventListener("click", (e) => {
          e.stopPropagation()
          this._removeTag(tag.id)
        })
        this.dropdownTarget.appendChild(row)
      }
    }

    // Available tags section
    if (available.length > 0) {
      if (this._tags.length > 0) {
        const divider = document.createElement("div")
        divider.className = "my-1"
        divider.style.cssText = "height: 1px; background: var(--toolbar-border);"
        this.dropdownTarget.appendChild(divider)
      }

      const header = document.createElement("p")
      header.className = "px-3 pt-2 pb-1 text-[10px] uppercase tracking-wider font-semibold"
      header.style.color = "var(--theme-text-faint)"
      header.textContent = "Adicionar"
      this.dropdownTarget.appendChild(header)

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

    if (this._tags.length === 0 && available.length === 0) {
      const empty = document.createElement("p")
      empty.className = "px-3 py-2 text-xs"
      empty.style.color = "var(--theme-text-faint)"
      empty.textContent = "Nenhuma tag disponível"
      this.dropdownTarget.appendChild(empty)
    }

    this.dropdownTarget.classList.remove("hidden")
  }

  _closeDropdown() {
    if (!this.hasDropdownTarget) return
    this._dropdownOpen = false
    this.dropdownTarget.classList.add("hidden")
  }

  async _addTag(tag) {
    this._tags.push({ id: tag.id, name: tag.name, color_hex: tag.color_hex })
    this._renderBadge()
    this._openDropdown() // refresh dropdown contents

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
    this._renderBadge()
    if (this._dropdownOpen) this._openDropdown() // refresh dropdown contents

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
