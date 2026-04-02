export class RevisionManager {
  constructor(config, callbacks) {
    this._config = config
    this._cb = callbacks
    this._open = false
    this._loaded = false
    this._byId = new Map()
    this._hoveredId = null
    this._selected = {
      id: config.initialRevisionId || null,
      kind: config.initialRevisionKind || null,
      isHead: config.initialRevisionId && config.initialRevisionId === config.headRevisionId
    }
    this._selectedContent = config.initialContent || ""
    this._workingContent = this._selectedContent
  }

  get isOpen() { return this._open }
  get selectedContent() { return this._selectedContent }
  get workingContent() { return this._workingContent }
  set workingContent(val) { this._workingContent = val }

  hasPendingEdits() {
    return this._workingContent !== this._selectedContent
  }

  shouldShowRestore() {
    return !!(
      this._selected?.id &&
      this._selected?.kind === "checkpoint" &&
      !this._selected?.isHead &&
      !this.hasPendingEdits()
    )
  }

  async toggleMenu() {
    this._open = !this._open
    this._syncMenuVisibility()

    if (this._open && !this._loaded) {
      await this._loadRevisions()
    }
  }

  previewRevision(revisionId) {
    const revision = this._findRevision(revisionId)
    if (!revision) return null
    this._hoveredId = revision.id
    return revision
  }

  clearPreview(relatedTarget, menuElement) {
    if (!this._hoveredId) return false
    if (relatedTarget && menuElement?.contains(relatedTarget)) return false
    this._hoveredId = null
    return true
  }

  selectRevision(revisionId) {
    const revision = this._findRevision(revisionId)
    if (!revision) return null

    this._hoveredId = null
    this._selected = {
      id: revision.id,
      kind: "checkpoint",
      isHead: !!revision.is_head
    }
    this._selectedContent = revision.content_markdown || ""
    this._workingContent = this._selectedContent
    this.close()
    return revision
  }

  close() {
    if (!this._open) return
    this._hoveredId = null
    this._open = false
    this._syncMenuVisibility()
  }

  async restoreSelected(slug) {
    const revisionId = this._selected?.id
    if (!revisionId) return false
    if (!window.confirm("Restaurar esta versão? O conteúdo e as propriedades serão restaurados.")) return false

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const response = await fetch(`/notes/${slug}/revisions/${revisionId}/restore`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        }
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this._loaded = false
      this.close()
      return true
    } catch (error) {
      console.error("Revision restore error:", error)
      return false
    }
  }

  onCheckpointSaved(headRevisionId) {
    this._selected = {
      id: headRevisionId || this._selected.id,
      kind: "checkpoint",
      isHead: true
    }
    this._selectedContent = this._cb.getCurrentContent()
    this._workingContent = this._selectedContent
  }

  hydrateFromPayload(revision, headRevisionId) {
    this._open = false
    this._loaded = false
    this._byId = new Map()
    this._hoveredId = null
    this._selected = {
      id: revision.id || null,
      kind: revision.kind || null,
      isHead: revision.id && revision.id === headRevisionId
    }
    this._selectedContent = revision.content_markdown || ""
    this._workingContent = this._selectedContent
  }

  renderPrimaryAction(button) {
    if (!button) return
    const isRestore = this.shouldShowRestore()

    button.title = isRestore ? "Restaurar esta versao" : "Salvar versão (checkpoint)"
    button.style.background = isRestore ? "#dc2626" : "var(--theme-accent)"
    button.innerHTML = isRestore ? `
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M3 12a9 9 0 109-9"/><path d="M3 3v6h6"/>
      </svg>
      Restaurar
    ` : `
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/>
        <polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/>
      </svg>
      Salvar
    `
  }

  // ── Private ──────────────────────────────────────────────

  _syncMenuVisibility() {
    this._cb.syncMenuVisibility(this._open)
  }

  async _loadRevisions() {
    const listEl = this._cb.getListElement()
    if (!listEl) return

    listEl.innerHTML = `
      <li class="px-3 py-2 text-xs" style="color: var(--theme-text-faint)">Carregando...</li>
    `

    try {
      const response = await fetch(this._config.revisionsUrl, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const revisions = await response.json()
      this._loaded = true
      this._byId = new Map(revisions.map((r) => [String(r.id), r]))
      this._renderRevisions(listEl, revisions)
    } catch (error) {
      console.error("Revisions load error:", error)
      listEl.innerHTML = `
        <li class="px-3 py-2 text-xs text-red-400">Nao foi possivel carregar as versoes.</li>
      `
    }
  }

  _renderRevisions(listEl, revisions) {
    if (!revisions.length) {
      listEl.innerHTML = `
        <li class="px-3 py-2 text-xs" style="color: var(--theme-text-faint)">Nenhuma versao salva.</li>
      `
      return
    }

    listEl.innerHTML = revisions.map((revision) => {
      const createdAt = new Date(revision.created_at).toLocaleString("pt-BR", {
        dateStyle: "short",
        timeStyle: "short"
      })
      const diffBadges = this._renderPropsDiffBadges(revision.properties_diff)
      return `
        <li class="border-b last:border-b-0"
            style="border-color: var(--toolbar-border)">
          <button type="button"
                  class="revision-entry w-full text-left ${revision.is_head ? "is-head" : ""}"
                  data-revision-id="${revision.id}"
                  data-action="mouseenter->editor#previewRevision click->editor#selectRevision">
            <span class="min-w-0 block">
              <span class="flex items-center gap-2">
                <span class="text-xs font-semibold text-gray-200">${createdAt}</span>
                ${revision.is_head ? '<span class="rounded px-1.5 py-0.5 text-[10px] font-semibold text-green-200" style="background: rgba(34, 197, 94, 0.16)">Atual</span>' : ""}
              </span>
              ${diffBadges}
            </span>
          </button>
        </li>
      `
    }).join("")
  }

  _renderPropsDiffBadges(diff) {
    if (!diff) return ""
    const badges = []
    for (const key of Object.keys(diff.added || {})) {
      badges.push(`<span class="text-green-400">+${key}</span>`)
    }
    for (const key of Object.keys(diff.removed || {})) {
      badges.push(`<span class="text-red-400">-${key}</span>`)
    }
    for (const key of Object.keys(diff.changed || {})) {
      badges.push(`<span class="text-yellow-400">~${key}</span>`)
    }
    if (!badges.length) return ""
    return `<span class="flex flex-wrap gap-1 mt-0.5 text-[10px] font-mono">${badges.join("")}</span>`
  }

  _findRevision(revisionId) {
    if (!revisionId) return null
    return this._byId.get(String(revisionId)) || null
  }
}
