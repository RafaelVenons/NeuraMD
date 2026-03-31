import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { createUrl: String, reorderUrl: String }
  static targets = [
    "list", "row",
    "createKey", "createType", "createLabel", "createDescription",
    "createConfigField", "createConfigContainer",
    "createError", "createErrorText",
    "editModal", "editTitle", "editId", "editLabel", "editDescription",
    "editConfigField", "editConfigContainer"
  ]

  connect() {
    this._editData = null
    this._dragState = null
  }

  // ── Create ────────────────────────────────────────

  async create(event) {
    event.preventDefault()
    this._hideError()

    const key = this.createKeyTarget.value.trim()
    const value_type = this.createTypeTarget.value
    const label = this.createLabelTarget.value.trim()
    const description = this.createDescriptionTarget.value.trim()
    const config = this._buildConfigFromCreate(value_type)

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ property_definition: { key, value_type, label, description, config } })
      })
      const data = await res.json()
      if (!res.ok) {
        this._showError(data.errors?.join(", ") || "Erro ao criar definição")
        return
      }
      window.location.reload()
    } catch (_) {
      this._showError("Erro de conexão")
    }
  }

  onTypeChange() {
    const type = this.createTypeTarget.value
    this._renderConfigFields(type, this.createConfigContainerTarget, this.createConfigFieldTarget, {})
  }

  // ── Edit ──────────────────────────────────────────

  editRow(event) {
    const row = event.target.closest("[data-id]")
    if (!row) return
    const id = row.dataset.id

    const label = row.querySelector(".propdef-row-label")?.textContent || ""
    const desc = row.querySelector(".propdef-row-desc")?.textContent || ""
    const type = row.querySelector(".propdef-row-type")?.textContent || ""
    const configText = row.querySelector(".propdef-row-config")?.textContent || ""

    this._editData = { id, type }
    this.editIdTarget.value = id
    this.editLabelTarget.value = label
    this.editDescriptionTarget.value = desc

    const config = this._parseConfigFromRow(type, configText)
    this._renderConfigFields(type, this.editConfigContainerTarget, this.editConfigFieldTarget, config)

    this.editTitleTarget.textContent = `Editar: ${label || id}`
    this.editModalTarget.classList.remove("hidden")
  }

  async saveEdit(event) {
    event.preventDefault()
    if (!this._editData) return

    const id = this._editData.id
    const label = this.editLabelTarget.value.trim()
    const description = this.editDescriptionTarget.value.trim()
    const config = this._buildConfigFromContainer(this._editData.type, this.editConfigContainerTarget)

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const res = await fetch(`${this.createUrlValue}/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ property_definition: { label, description, config } })
      })
      if (res.ok) window.location.reload()
    } catch (_) {}
  }

  closeEdit() {
    this.editModalTarget.classList.add("hidden")
    this._editData = null
  }

  // ── Archive ───────────────────────────────────────

  async archiveRow(event) {
    const row = event.target.closest("[data-id]")
    if (!row) return
    if (!confirm("Arquivar esta definição? Propriedades existentes não serão removidas.")) return

    const id = row.dataset.id
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const res = await fetch(`${this.createUrlValue}/${id}`, {
        method: "DELETE",
        headers: { Accept: "application/json", "X-CSRF-Token": csrf }
      })
      if (res.ok) row.remove()
    } catch (_) {}
  }

  // ── Reorder (drag) ────────────────────────────────

  startDrag(event) {
    const row = event.target.closest("[data-id]")
    if (!row) return
    event.preventDefault()

    this._dragState = { row, startY: event.clientY, initialIndex: this._rowIndex(row) }
    row.classList.add("propdef-row--dragging")

    this._onMouseMove = (e) => this._handleDragMove(e)
    this._onMouseUp = () => this._handleDragEnd()
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
  }

  _handleDragMove(event) {
    if (!this._dragState) return
    const { row } = this._dragState
    const list = this.listTarget
    const rows = [...list.querySelectorAll("[data-id]")]
    const rowRect = row.getBoundingClientRect()
    const y = event.clientY

    for (const sibling of rows) {
      if (sibling === row) continue
      const rect = sibling.getBoundingClientRect()
      const mid = rect.top + rect.height / 2
      if (y < mid && rowRect.top > rect.top) {
        list.insertBefore(row, sibling)
        break
      } else if (y > mid && rowRect.top < rect.top) {
        list.insertBefore(row, sibling.nextSibling)
        break
      }
    }
  }

  async _handleDragEnd() {
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)

    if (!this._dragState) return
    this._dragState.row.classList.remove("propdef-row--dragging")

    const ids = [...this.listTarget.querySelectorAll("[data-id]")].map(r => r.dataset.id)
    this._dragState = null

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    try {
      await fetch(this.reorderUrlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ ids })
      })
    } catch (_) {}
  }

  _rowIndex(row) {
    return [...this.listTarget.querySelectorAll("[data-id]")].indexOf(row)
  }

  // ── Config rendering ──────────────────────────────

  _renderConfigFields(type, container, wrapper, config) {
    container.innerHTML = ""

    if (type === "enum" || type === "multi_enum") {
      wrapper.classList.remove("hidden")
      const label = document.createElement("p")
      label.className = "propdef-hint"
      label.textContent = "Uma opção por linha"
      const textarea = document.createElement("textarea")
      textarea.className = "propdef-input propdef-config-options"
      textarea.rows = 4
      textarea.value = (config.options || []).join("\n")
      textarea.dataset.configKey = "options"
      container.appendChild(label)
      container.appendChild(textarea)
    } else if (type === "number") {
      wrapper.classList.remove("hidden")
      const row = document.createElement("div")
      row.className = "propdef-config-number-row"
      const minInput = document.createElement("input")
      minInput.type = "number"
      minInput.className = "propdef-input"
      minInput.placeholder = "Min (opcional)"
      minInput.value = config.min ?? ""
      minInput.dataset.configKey = "min"
      const maxInput = document.createElement("input")
      maxInput.type = "number"
      maxInput.className = "propdef-input"
      maxInput.placeholder = "Max (opcional)"
      maxInput.value = config.max ?? ""
      maxInput.dataset.configKey = "max"
      row.appendChild(minInput)
      row.appendChild(maxInput)
      container.appendChild(row)
    } else {
      wrapper.classList.add("hidden")
    }
  }

  _buildConfigFromCreate(type) {
    return this._buildConfigFromContainer(type, this.createConfigContainerTarget)
  }

  _buildConfigFromContainer(type, container) {
    if (type === "enum" || type === "multi_enum") {
      const textarea = container.querySelector("[data-config-key='options']")
      if (!textarea) return {}
      const options = textarea.value.split("\n").map(s => s.trim()).filter(Boolean)
      return { options }
    }
    if (type === "number") {
      const config = {}
      const min = container.querySelector("[data-config-key='min']")
      const max = container.querySelector("[data-config-key='max']")
      if (min?.value !== "") config.min = Number(min.value)
      if (max?.value !== "") config.max = Number(max.value)
      return config
    }
    return {}
  }

  _parseConfigFromRow(type, configText) {
    if (type === "enum" || type === "multi_enum") {
      const match = configText.match(/Opções:\s*(.+)/)
      if (match) return { options: match[1].split(",").map(s => s.trim()) }
    }
    if (type === "number") {
      const config = {}
      const match = configText.match(/Range:\s*(.+?)\s*—\s*(.+)/)
      if (match) {
        if (match[1] !== "−∞") config.min = Number(match[1])
        if (match[2] !== "∞") config.max = Number(match[2])
      }
      return config
    }
    return {}
  }

  // ── Helpers ───────────────────────────────────────

  _showError(msg) {
    this.createErrorTarget.style.display = ""
    this.createErrorTextTarget.textContent = msg
  }

  _hideError() {
    this.createErrorTarget.style.display = "none"
  }
}
