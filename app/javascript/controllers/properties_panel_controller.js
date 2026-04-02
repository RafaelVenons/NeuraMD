import { Controller } from "@hotwired/stimulus"

// Manages the note properties side panel.
// Renders type-specific inputs for each property, supports add/remove,
// saves on blur/change via PATCH, and shows validation errors inline.
export default class extends Controller {
  static values = {
    propertiesUrl: String,
    aliasesUrl: String,
    initialDefinitions: { type: Array, default: [] },
    initialProperties: { type: Object, default: {} },
    initialErrors: { type: Object, default: {} },
    initialAliases: { type: Array, default: [] }
  }
  static targets = ["list", "addButton", "addDropdown"]

  connect() {
    this._definitions = this.initialDefinitionsValue
    this._properties = this.initialPropertiesValue
    this._errors = this.initialErrorsValue
    this._aliases = this.initialAliasesValue
    this._addDropdownOpen = false

    this._onDocClick = (e) => {
      if (!this._addDropdownOpen) return
      if (this.addDropdownTarget.contains(e.target)) return
      if (this.addButtonTarget.contains(e.target)) return
      this._closeAddDropdown()
    }
    document.addEventListener("click", this._onDocClick)

    this._render()
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
  }

  hydrateNoteContext(payload) {
    this._definitions = payload.property_definitions || []
    this._properties = payload.properties || {}
    this._errors = payload.properties_errors || {}
    this._aliases = payload.aliases || []
    this.propertiesUrlValue = payload.urls?.properties || this.propertiesUrlValue
    this.aliasesUrlValue = payload.urls?.aliases || this.aliasesUrlValue
    this._render()
    this._closeAddDropdown()
  }

  toggleAddDropdown() {
    if (this._addDropdownOpen) this._closeAddDropdown()
    else this._openAddDropdown()
  }

  // ── Rendering ───────────────────────────────────────────

  _render() {
    if (!this.hasListTarget) return
    this.listTarget.innerHTML = ""

    this.listTarget.appendChild(this._buildAliasesSection())

    const setKeys = Object.keys(this._properties)
    const defsWithValues = this._definitions.filter(d => setKeys.includes(d.key))

    if (defsWithValues.length === 0 && this._aliases.length === 0) {
      const empty = document.createElement("p")
      empty.className = "properties-empty"
      empty.textContent = "Nenhuma propriedade definida"
      this.listTarget.appendChild(empty)
      return
    }

    for (const def of defsWithValues) {
      const value = this._properties[def.key]
      const errors = this._errors[def.key]
      this.listTarget.appendChild(this._buildRow(def, value, errors))
    }
  }

  _buildRow(def, value, errors) {
    const row = document.createElement("div")
    row.className = "properties-row"
    if (errors) row.classList.add("properties-row--error")

    const label = document.createElement("label")
    label.className = "properties-row-label"
    label.textContent = def.label || def.key
    if (def.description) label.title = def.description

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "properties-row-remove"
    removeBtn.title = "Remover propriedade"
    removeBtn.innerHTML = "&times;"
    removeBtn.addEventListener("click", () => this._removeProperty(def.key))

    const header = document.createElement("div")
    header.className = "properties-row-header"
    header.appendChild(label)
    header.appendChild(removeBtn)

    const input = this._buildInput(def, value)
    row.appendChild(header)
    row.appendChild(input)

    if (errors) {
      const errEl = document.createElement("p")
      errEl.className = "properties-row-error"
      errEl.textContent = errors.join(", ")
      row.appendChild(errEl)
    }

    return row
  }

  _buildInput(def, value) {
    switch (def.value_type) {
      case "boolean":
        return this._buildCheckbox(def, value)
      case "enum":
        return this._buildSelect(def, value)
      case "multi_enum":
        return this._buildMultiEnum(def, value)
      case "long_text":
        return this._buildTextarea(def, value)
      case "number":
        return this._buildNumberInput(def, value)
      case "date":
        return this._buildDateInput(def, value, "date")
      case "datetime":
        return this._buildDateInput(def, value, "datetime-local")
      default:
        return this._buildTextInput(def, value)
    }
  }

  _buildTextInput(def, value) {
    const input = document.createElement("input")
    input.type = def.value_type === "url" ? "url" : "text"
    input.className = "properties-input"
    input.value = value ?? ""
    input.placeholder = def.label || def.key
    input.addEventListener("blur", () => this._saveProperty(def.key, input.value))
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") input.blur() })
    return input
  }

  _buildNumberInput(def, value) {
    const input = document.createElement("input")
    input.type = "number"
    input.className = "properties-input"
    input.value = value ?? ""
    if (def.config?.min != null) input.min = def.config.min
    if (def.config?.max != null) input.max = def.config.max
    input.addEventListener("blur", () => {
      const val = input.value === "" ? null : Number(input.value)
      this._saveProperty(def.key, val)
    })
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") input.blur() })
    return input
  }

  _buildDateInput(def, value, type) {
    const input = document.createElement("input")
    input.type = type
    input.className = "properties-input"
    input.value = value ?? ""
    input.addEventListener("change", () => this._saveProperty(def.key, input.value || null))
    return input
  }

  _buildTextarea(def, value) {
    const textarea = document.createElement("textarea")
    textarea.className = "properties-input properties-textarea"
    textarea.value = value ?? ""
    textarea.rows = 2
    textarea.placeholder = def.label || def.key
    textarea.addEventListener("blur", () => this._saveProperty(def.key, textarea.value))
    return textarea
  }

  _buildCheckbox(def, value) {
    const wrapper = document.createElement("label")
    wrapper.className = "properties-checkbox-wrapper"
    const checkbox = document.createElement("input")
    checkbox.type = "checkbox"
    checkbox.className = "properties-checkbox"
    checkbox.checked = value === true || value === "true"
    checkbox.addEventListener("change", () => this._saveProperty(def.key, checkbox.checked))
    const text = document.createElement("span")
    text.className = "text-xs"
    text.style.color = "var(--theme-text-secondary)"
    text.textContent = checkbox.checked ? "Sim" : "Não"
    checkbox.addEventListener("change", () => { text.textContent = checkbox.checked ? "Sim" : "Não" })
    wrapper.appendChild(checkbox)
    wrapper.appendChild(text)
    return wrapper
  }

  _buildSelect(def, value) {
    const select = document.createElement("select")
    select.className = "properties-input"
    const emptyOpt = document.createElement("option")
    emptyOpt.value = ""
    emptyOpt.textContent = "—"
    select.appendChild(emptyOpt)
    for (const opt of (def.config?.options || [])) {
      const option = document.createElement("option")
      option.value = opt
      option.textContent = opt
      if (opt === value) option.selected = true
      select.appendChild(option)
    }
    select.addEventListener("change", () => this._saveProperty(def.key, select.value || null))
    return select
  }

  _buildMultiEnum(def, value) {
    const container = document.createElement("div")
    container.className = "properties-multi-enum"
    const selected = Array.isArray(value) ? value : []
    for (const opt of (def.config?.options || [])) {
      const label = document.createElement("label")
      label.className = "properties-multi-enum-option"
      const cb = document.createElement("input")
      cb.type = "checkbox"
      cb.value = opt
      cb.checked = selected.includes(opt)
      cb.addEventListener("change", () => {
        const checked = container.querySelectorAll("input:checked")
        const vals = Array.from(checked).map(c => c.value)
        this._saveProperty(def.key, vals.length > 0 ? vals : null)
      })
      const span = document.createElement("span")
      span.textContent = opt
      label.appendChild(cb)
      label.appendChild(span)
      container.appendChild(label)
    }
    return container
  }

  // ── Add / Remove ────────────────────────────────────────

  _openAddDropdown() {
    if (!this.hasAddDropdownTarget) return
    this._addDropdownOpen = true

    const usedKeys = new Set(Object.keys(this._properties))
    const available = this._definitions.filter(d => !usedKeys.has(d.key))

    this.addDropdownTarget.innerHTML = ""

    if (available.length === 0) {
      const p = document.createElement("p")
      p.className = "px-3 py-2 text-xs"
      p.style.color = "var(--theme-text-faint)"
      p.textContent = "Todas as propriedades já estão definidas"
      this.addDropdownTarget.appendChild(p)
    } else {
      for (const def of available) {
        const btn = document.createElement("button")
        btn.type = "button"
        btn.className = "properties-add-option"
        btn.innerHTML = `
          <span class="properties-add-option-type">${def.value_type}</span>
          <span>${this._escapeHtml(def.label || def.key)}</span>
        `
        btn.addEventListener("click", () => this._addProperty(def))
        this.addDropdownTarget.appendChild(btn)
      }
    }

    this.addDropdownTarget.classList.remove("hidden")
  }

  _closeAddDropdown() {
    if (!this.hasAddDropdownTarget) return
    this._addDropdownOpen = false
    this.addDropdownTarget.classList.add("hidden")
  }

  _addProperty(def) {
    this._closeAddDropdown()
    const defaultValue = this._defaultValueForType(def.value_type)
    this._saveProperty(def.key, defaultValue)
  }

  _defaultValueForType(type) {
    switch (type) {
      case "boolean": return false
      case "number": return 0
      case "text": case "long_text": case "url": case "note_reference": return ""
      case "enum": return ""
      case "multi_enum": case "list": return []
      case "date": return new Date().toISOString().split("T")[0]
      case "datetime": return new Date().toISOString().slice(0, 16)
      default: return ""
    }
  }

  async _removeProperty(key) {
    await this._saveProperty(key, null)
  }

  // ── Save ────────────────────────────────────────────────

  async _saveProperty(key, value) {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const response = await fetch(this.propertiesUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({ changes: { [key]: value } })
      })
      if (!response.ok) return

      const data = await response.json()
      this._properties = data.properties || {}
      this._errors = data.properties_errors || {}
      this._render()
    } catch (_) {}
  }

  // ── Aliases ─────────────────────────────────────────────

  _buildAliasesSection() {
    const section = document.createElement("div")
    section.className = "aliases-section"

    const header = document.createElement("div")
    header.className = "aliases-header"
    header.innerHTML = `<span class="aliases-label">Aliases</span>`
    section.appendChild(header)

    const chipContainer = document.createElement("div")
    chipContainer.className = "aliases-chips"

    for (const alias of this._aliases) {
      const chip = document.createElement("span")
      chip.className = "alias-chip"
      chip.innerHTML = `
        ${this._escapeHtml(alias)}
        <button type="button" class="alias-chip-remove" title="Remover">&times;</button>
      `
      chip.querySelector(".alias-chip-remove").addEventListener("click", () => {
        this._aliases = this._aliases.filter(a => a !== alias)
        this._saveAliases()
      })
      chipContainer.appendChild(chip)
    }

    const input = document.createElement("input")
    input.type = "text"
    input.className = "alias-input"
    input.placeholder = "Novo alias…"
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && input.value.trim()) {
        e.preventDefault()
        const val = input.value.trim()
        if (!this._aliases.includes(val)) {
          this._aliases.push(val)
          this._saveAliases()
        }
        input.value = ""
      }
    })
    chipContainer.appendChild(input)
    section.appendChild(chipContainer)

    return section
  }

  async _saveAliases() {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const response = await fetch(this.aliasesUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({ aliases: this._aliases })
      })
      if (!response.ok) return

      const data = await response.json()
      this._aliases = data.aliases || []
      this._render()
    } catch (_) {}
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  // ── Revision preview ──────────────────────────────────────

  previewProperties(props) {
    if (!this.hasListTarget) return
    this._previewActive = true
    this._savedProperties = this._properties
    this._savedErrors = this._errors
    this._properties = props
    this._errors = {}
    this._render()
    this.listTarget.classList.add("opacity-60", "pointer-events-none")
  }

  clearPreview() {
    if (!this._previewActive || !this.hasListTarget) return
    this._previewActive = false
    this._properties = this._savedProperties
    this._errors = this._savedErrors
    this._render()
    this.listTarget.classList.remove("opacity-60", "pointer-events-none")
  }
}
