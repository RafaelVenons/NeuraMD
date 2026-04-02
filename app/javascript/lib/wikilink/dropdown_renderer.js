export class DropdownRenderer {
  constructor(dropdownElement, roleLabels) {
    this._dropdown = dropdownElement
    this._roleLabels = roleLabels
  }

  render(suggestions, activeIndex, currentRole, onSelect, escapeHtml) {
    if (suggestions.length === 0) {
      this.close()
      return
    }

    const roleKey = currentRole ?? "null"
    const roleLabel = this._roleLabels[roleKey]
    const roleClass = `wikilink-role-${roleKey}`

    this._dropdown.innerHTML = `
      <div class="wikilink-role-bar">
        <span class="wikilink-role-hint">← →</span>
        <span class="wikilink-role-current ${roleClass}">${roleLabel}</span>
      </div>
      ${suggestions.map((item, i) => `
        <button
          class="wikilink-suggestion ${i === activeIndex ? "active" : ""}"
          data-index="${i}"
          type="button"
        >
          <span>${escapeHtml(item.title || item.label)}</span>
          ${item.matched_alias ? `<span class="wikilink-alias-hint">aka: ${escapeHtml(item.matched_alias)}</span>` : ""}
          ${item.description ? `<span class="block mt-1 text-xs opacity-70">${escapeHtml(item.description)}</span>` : ""}
        </button>
      `).join("")}
    `

    this._dropdown.querySelectorAll("button").forEach((btn, i) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault()
        onSelect(i, suggestions[i])
      })
    })

    this._dropdown.hidden = false
  }

  position(insertStart, cmView, paneRect) {
    if (!cmView || insertStart == null) return
    const coords = cmView.coordsAtPos(insertStart)
    if (!coords) return

    const spaceBelow = window.innerHeight - coords.bottom

    if (spaceBelow >= 80) {
      this._dropdown.style.top = `${coords.bottom - paneRect.top + 4}px`
      this._dropdown.style.bottom = "auto"
    } else {
      this._dropdown.style.top = "auto"
      this._dropdown.style.bottom = `${paneRect.bottom - coords.top + 4}px`
    }

    const left = coords.left - paneRect.left
    const maxLeft = paneRect.width - 240 - 8
    this._dropdown.style.left = `${Math.max(4, Math.min(left, maxLeft))}px`
  }

  scrollActiveIntoView() {
    if (this._dropdown.hidden) return
    const active = this._dropdown.querySelector(".wikilink-suggestion.active")
    if (active) active.scrollIntoView({ block: "nearest" })
  }

  isOpen() {
    return !this._dropdown.hidden
  }

  close() {
    this._dropdown.hidden = true
  }
}
