export class EmbedLoader {
  constructor(maxDepth) {
    this._cache = new Map()
    this._maxDepth = maxDepth
  }

  async load(outputElement, renderVersion, isStale, parseMarkdown, stripBlockMarkers) {
    await this._loadLevel(outputElement, renderVersion, isStale, parseMarkdown, stripBlockMarkers, 0)
  }

  async _loadLevel(outputElement, renderVersion, isStale, parseMarkdown, stripBlockMarkers, depth) {
    if (depth >= this._maxDepth) {
      this._convertEmbedsToLinks(outputElement)
      return
    }

    const containers = Array.from(
      outputElement.querySelectorAll(".embed-container.embed-loading")
    )
    if (containers.length === 0) return

    const fetches = containers.map(container =>
      this._fetchEmbed(container, renderVersion, isStale, parseMarkdown, stripBlockMarkers)
    )
    await Promise.allSettled(fetches)

    if (isStale()) return
    await this._loadLevel(outputElement, renderVersion, isStale, parseMarkdown, stripBlockMarkers, depth + 1)
  }

  async _fetchEmbed(container, renderVersion, isStale, parseMarkdown, stripBlockMarkers) {
    const uuid = container.dataset.embedUuid
    const heading = container.dataset.embedHeading
    const block = container.dataset.embedBlock

    const cacheKey = `${uuid}:${heading || ""}:${block || ""}`
    const cached = this._cache.get(cacheKey)

    let data
    if (cached) {
      data = cached
    } else {
      try {
        const params = new URLSearchParams()
        if (heading) params.set("heading", heading)
        if (block) params.set("block", block)

        const response = await fetch(`/notes/${uuid}/embed?${params}`, {
          headers: { Accept: "application/json" },
          credentials: "same-origin"
        })

        if (isStale()) return
        if (!response.ok) {
          this._markEmbedBroken(container)
          return
        }

        data = await response.json()
        if (!data.found) {
          this._markEmbedBroken(container)
          return
        }

        this._cache.set(cacheKey, data)
      } catch (_) {
        this._markEmbedBroken(container)
        return
      }
    }

    const html = parseMarkdown(data.markdown || "")

    const contentEl = container.querySelector(".embed-content")
    contentEl.innerHTML = html

    const headerEl = container.querySelector(".embed-header")
    headerEl.innerHTML = `<a href="/notes/${data.note_slug}" class="embed-source-link">${data.note_title}</a>`

    container.classList.remove("embed-loading")
    container.classList.add("embed-loaded")

    stripBlockMarkers(contentEl)
  }

  _markEmbedBroken(container) {
    container.classList.remove("embed-loading")
    container.classList.add("embed-broken")
    const contentEl = container.querySelector(".embed-content")
    contentEl.innerHTML = '<span class="embed-error">Conteudo nao encontrado</span>'
  }

  _convertEmbedsToLinks(outputElement) {
    outputElement.querySelectorAll(".embed-container.embed-loading").forEach(container => {
      const uuid = container.dataset.embedUuid
      const heading = container.dataset.embedHeading
      const block = container.dataset.embedBlock
      const display = container.querySelector(".embed-header")?.textContent || "Embed"
      const fragment = heading ? `#${heading}` : block ? `#${block}` : ""
      const link = document.createElement("a")
      link.href = `/notes/${uuid}${fragment}`
      link.className = "wikilink wikilink-null"
      link.textContent = display
      container.replaceWith(link)
    })
  }
}
