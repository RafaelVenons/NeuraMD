import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "input", "results", "status", "regex"]
  static values = { searchUrl: String }

  connect() {
    this._results = []
    this._activeIndex = -1
    this._debounceTimer = null
    this._boundKeydown = this._handleGlobalKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundKeydown)
    clearTimeout(this._debounceTimer)
  }

  open(event) {
    event?.preventDefault()
    if (this.isOpen()) return
    this.dialogTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.inputTarget.select()
    this._renderPrompt()
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.classList.add("hidden")
    this._resetResults()
  }

  toggle(event) {
    if (this.isOpen()) {
      this.close(event)
    } else {
      this.open(event)
    }
  }

  search() {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this._fetchResults(), 120)
  }

  handleInputKeydown(event) {
    if (event.isComposing || event.keyCode === 229) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this._moveActive(-1)
        break
      case "Enter":
        if (this._activeIndex >= 0) {
          event.preventDefault()
          this._visit(this._results[this._activeIndex])
        }
        break
      case "Escape":
        this.close(event)
        break
    }
  }

  toggleRegex() {
    if (!this.dialogTarget.classList.contains("hidden")) this._fetchResults()
  }

  hoverResult(event) {
    const nextIndex = Number(event.currentTarget.dataset.index)
    if (nextIndex === this._activeIndex) return
    this._activeIndex = nextIndex
    this._renderResults()
  }

  choose(event) {
    event.preventDefault()
    event.stopPropagation()
    const result = this._results[Number(event.currentTarget.dataset.index)]
    if (!result) return
    this._visit(result)
  }

  async _fetchResults() {
    const query = this.inputTarget.value.trim()
    if (!query) {
      this._renderPrompt()
      return
    }

    this.statusTarget.textContent = "Buscando..."

    const params = new URLSearchParams({
      q: query,
      mode: "finder",
      limit: "8"
    })
    if (this.regexTarget.checked) params.set("regex", "1")

    try {
      const response = await fetch(`${this.searchUrlValue}?${params.toString()}`, {
        headers: { Accept: "application/json" }
      })
      const payload = await response.json()

      if (!response.ok) {
        this._results = []
        this._activeIndex = -1
        this.resultsTarget.innerHTML = ""
        this.statusTarget.textContent = payload.error || "Nao foi possivel buscar."
        return
      }

      this._results = payload.results || []
      this._activeIndex = this._results.length > 0 ? 0 : -1
      this._renderResults(payload.meta)
    } catch (_) {
      this._results = []
      this._activeIndex = -1
      this.resultsTarget.innerHTML = ""
      this.statusTarget.textContent = "Erro de rede ao buscar."
    }
  }

  _renderPrompt() {
    this._resetResults()
    this.statusTarget.textContent = "Digite para buscar por titulo ou conteudo"
  }

  _resetResults() {
    this._results = []
    this._activeIndex = -1
    this.resultsTarget.innerHTML = ""
    this.inputTarget.value = ""
    this.regexTarget.checked = false
  }

  _moveActive(delta) {
    if (this._results.length === 0) return
    const lastIndex = this._results.length - 1
    this._activeIndex = Math.max(0, Math.min(lastIndex, this._activeIndex + delta))
    this._renderResults()
  }

  _renderResults(meta = null) {
    if (this._results.length === 0) {
      this.resultsTarget.innerHTML = ""
      this.statusTarget.textContent = "Nenhuma nota encontrada"
      return
    }

    this.resultsTarget.innerHTML = this._results.map((result, index) => `
      <a href="/notes/${result.slug}"
         class="note-finder-result ${index === this._activeIndex ? "is-active" : ""}"
         data-index="${index}"
         data-action="mouseenter->note-finder#hoverResult click->note-finder#choose">
        <span class="note-finder-result__title">${this._escapeHtml(result.title)}</span>
        <span class="note-finder-result__meta">${this._escapeHtml(result.detected_language || "auto")} · ${this._formatDate(result.updated_at)}</span>
        <span class="note-finder-result__snippet">${this._escapeHtml(result.snippet || "")}</span>
      </a>
    `).join("")

    const suffix = meta?.has_more ? " · mais resultados disponiveis" : ""
    this.statusTarget.textContent = `${this._results.length} resultados${suffix}`
  }

  _visit(result) {
    if (!result) return
    this.close()
    const href = `/notes/${result.slug}`
    if (window.Turbo?.visit) {
      window.Turbo.visit(href)
    } else {
      window.location.href = href
    }
  }

  _handleGlobalKeydown(event) {
    if (event.isComposing || event.keyCode === 229) return
    const ctrl = event.ctrlKey || event.metaKey

    if (event.key === "Escape" && this.isOpen()) {
      this.close(event)
      return
    }

    if (ctrl && event.shiftKey && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.toggle()
    }
  }

  isOpen() {
    return !this.dialogTarget.classList.contains("hidden")
  }

  _formatDate(value) {
    if (!value) return ""
    return new Date(value).toLocaleString("pt-BR", {
      dateStyle: "short",
      timeStyle: "short"
    })
  }

  _escapeHtml(value) {
    return (value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
