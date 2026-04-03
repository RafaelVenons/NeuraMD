import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["results", "pagination", "filterInput", "dslErrors", "title"]
  static values = {
    resultsUrl: String,
    updateUrl: String,
    viewId: String,
    displayType: String,
    columns: Array,
    sortField: String,
    sortDirection: String,
    filter: String
  }

  connect() {
    this._page = 1
    this._notes = []
    this._fetchResults()
  }

  async _fetchResults(append = false) {
    const url = new URL(this.resultsUrlValue, window.location.origin)
    url.searchParams.set("page", this._page)

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      const data = await response.json()

      if (append) {
        this._notes = this._notes.concat(data.notes)
      } else {
        this._notes = data.notes
      }

      this._hasMore = data.has_more
      this._renderDslErrors(data.dsl_errors || [])
      this._render()
    } catch (e) {
      this.resultsTarget.innerHTML = `<div class="nv-empty">Erro ao carregar resultados.</div>`
    }
  }

  _render() {
    if (this._notes.length === 0) {
      this.resultsTarget.innerHTML = `<div class="nv-empty">Nenhuma nota encontrada para este filtro.</div>`
      this.paginationTarget.innerHTML = ""
      return
    }

    const type = this.displayTypeValue
    if (type === "card") this._renderCards()
    else if (type === "list") this._renderList()
    else this._renderTable()

    this._renderPagination()
  }

  _renderTable() {
    const cols = this.columnsValue
    const sortField = this.sortFieldValue
    const sortDir = this.sortDirectionValue

    const ths = cols.map(col => {
      const icon = col === sortField ? (sortDir === "asc" ? "▲" : "▼") : ""
      return `<th data-action="click->note-view#sort" data-note-view-field-param="${this._esc(col)}">${this._esc(this._label(col))} <span class="nv-table__sort-icon">${icon}</span></th>`
    }).join("")

    const rows = this._notes.map(note => {
      const tds = cols.map(col => `<td>${this._cell(note, col)}</td>`).join("")
      return `<tr>${tds}</tr>`
    }).join("")

    this.resultsTarget.innerHTML = `<table class="nv-table"><thead><tr>${ths}</tr></thead><tbody>${rows}</tbody></table>`
  }

  _renderCards() {
    const cols = this.columnsValue.filter(c => c !== "title")
    const cards = this._notes.map(note => {
      const props = cols.map(col => {
        const val = this._resolveField(note, col)
        return val ? `<span class="nv-card__prop">${this._esc(this._label(col))}: ${this._esc(val)}</span>` : ""
      }).filter(Boolean).join("")

      return `<a href="/notes/${this._esc(note.slug)}" class="nv-card">
        <div class="nv-card__title">${this._esc(note.title)}</div>
        ${note.excerpt ? `<div class="nv-card__excerpt">${this._esc(note.excerpt)}</div>` : ""}
        ${props ? `<div class="nv-card__meta">${props}</div>` : ""}
      </a>`
    }).join("")

    this.resultsTarget.innerHTML = `<div class="nv-cards">${cards}</div>`
  }

  _renderList() {
    const cols = this.columnsValue.filter(c => c !== "title").slice(0, 3)
    const rows = this._notes.map(note => {
      const meta = cols.map(col => {
        const val = this._resolveField(note, col)
        return val ? `<span class="nv-list__meta">${this._esc(val)}</span>` : ""
      }).filter(Boolean).join("")

      return `<a href="/notes/${this._esc(note.slug)}" class="nv-list__row">
        <span class="nv-list__title">${this._esc(note.title)}</span>
        ${meta}
      </a>`
    }).join("")

    this.resultsTarget.innerHTML = `<div class="nv-list">${rows}</div>`
  }

  _renderPagination() {
    if (this._hasMore) {
      this.paginationTarget.innerHTML = `<button class="nv-load-more" data-action="click->note-view#loadMore">Carregar mais</button>`
    } else {
      this.paginationTarget.innerHTML = ""
    }
  }

  _renderDslErrors(errors) {
    if (!this.hasDslErrorsTarget) return
    if (errors.length === 0) {
      this.dslErrorsTarget.innerHTML = ""
      return
    }
    const msgs = errors.map(e => `${e.operator}:${e.value} — ${e.message}`).join("; ")
    this.dslErrorsTarget.innerHTML = `<div class="nv-dsl-errors">${this._esc(msgs)}</div>`
  }

  // ── Actions ──────────────────────────────────────────────────────────

  async sort(event) {
    const field = event.params.field
    let dir = "asc"
    if (field === this.sortFieldValue) {
      dir = this.sortDirectionValue === "asc" ? "desc" : "asc"
    }

    await this._patch({ sort_config: JSON.stringify({ field, direction: dir }) })
    this.sortFieldValue = field
    this.sortDirectionValue = dir
    this._page = 1
    this._fetchResults()
  }

  async switchDisplay(event) {
    const type = event.params.type
    if (type === this.displayTypeValue) return

    await this._patch({ display_type: type })
    this.displayTypeValue = type

    // Update toggle buttons
    this.element.querySelectorAll(".nv-display-btn").forEach(btn => {
      btn.classList.toggle("is-active", btn.dataset.noteViewTypeParam === type)
    })

    this._render()
  }

  async updateFilter() {
    if (!this.hasFilterInputTarget) return
    const query = this.filterInputTarget.value.trim()

    await this._patch({ filter_query: query })
    this.filterValue = query
    this._page = 1
    this._fetchResults()
  }

  loadMore() {
    this._page++
    this._fetchResults(true)
  }

  async destroy() {
    if (!confirm("Excluir esta view?")) return

    await fetch(this.updateUrlValue, {
      method: "DELETE",
      headers: { "X-CSRF-Token": this._csrfToken(), Accept: "application/json" }
    })
    window.location.href = "/views"
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  async _patch(fields) {
    await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this._csrfToken(),
        Accept: "application/json"
      },
      body: JSON.stringify({ note_view: fields })
    })
  }

  _cell(note, col) {
    if (col === "title") {
      return `<a href="/notes/${this._esc(note.slug)}" class="nv-table__link">${this._esc(note.title)}</a>`
    }
    const val = this._resolveField(note, col)
    return val ? `<span class="nv-table__prop-cell">${this._esc(val)}</span>` : ""
  }

  _resolveField(note, col) {
    if (col === "title") return note.title
    if (col === "created_at" || col === "updated_at") return this._formatDate(note[col])
    return note.properties?.[col] || ""
  }

  _label(col) {
    const labels = { title: "Titulo", created_at: "Criado", updated_at: "Atualizado" }
    return labels[col] || col
  }

  _formatDate(value) {
    if (!value) return ""
    return new Date(value).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" })
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  _esc(str) {
    return (str || "").toString()
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
