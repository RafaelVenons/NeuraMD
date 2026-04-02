export class WikilinkValidator {
  constructor() {
    this._cache = new Map()
  }

  async validate(outputElement, renderVersion, isStale) {
    const links = Array.from(outputElement.querySelectorAll("a.wikilink[data-uuid]"))
    if (links.length === 0) return

    const pendingChecks = []

    links.forEach(link => {
      const uuid = link.dataset.uuid
      if (!uuid) return

      const cachedState = this._cache.get(uuid)

      if (cachedState === false) {
        this._replaceBrokenWikilink(link)
        return
      }

      if (cachedState?.ok) {
        this._applyHref(link, cachedState)
        return
      }

      pendingChecks.push(this._checkWikilink(uuid, renderVersion, isStale))
    })

    if (pendingChecks.length > 0) {
      await Promise.allSettled(pendingChecks)
    }

    if (isStale()) return

    outputElement.querySelectorAll("a.wikilink[data-uuid]").forEach(link => {
      const cachedState = this._cache.get(link.dataset.uuid)
      if (cachedState === false) {
        this._replaceBrokenWikilink(link)
      } else if (cachedState?.ok && cachedState.href) {
        this._applyHref(link, cachedState)
      }
    })
  }

  async _checkWikilink(uuid, renderVersion, isStale) {
    try {
      const response = await fetch(`/notes/${uuid}`, {
        method: "GET",
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })

      if (isStale()) return
      if (response.ok) {
        this._cache.set(uuid, { ok: true, href: this._canonicalHref(response) })
        return
      }

      if (response.status === 404) {
        this._cache.set(uuid, false)
        return
      }

      this._cache.delete(uuid)
    } catch (error) {
      if (isStale()) return
      this._cache.delete(uuid)
      console.warn("Failed to validate wikilink preview:", error)
    }
  }

  _canonicalHref(response) {
    try {
      const url = new URL(response.url, window.location.origin)
      return `${url.pathname}${url.search}${url.hash}`
    } catch (_) {
      return null
    }
  }

  _applyHref(link, cachedState) {
    if (!cachedState.href) return
    const base = cachedState.href.split("#")[0]
    const frag = link.dataset.headingSlug || link.dataset.blockId
    link.href = frag ? `${base}#${frag}` : cachedState.href
  }

  _replaceBrokenWikilink(link) {
    const broken = document.createElement("span")
    broken.className = "wikilink-broken"
    broken.textContent = link.textContent || ""
    broken.title = "Nota nao encontrada"
    link.replaceWith(broken)
  }
}
