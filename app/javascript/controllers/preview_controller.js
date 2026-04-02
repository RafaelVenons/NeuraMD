import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension, wikilinkExtension, embedExtension } from "lib/marked_extensions"
import { generateHeadingSlug } from "lib/heading_slug"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this._headingSlugCounts = new Map()
    const controller = this
    marked.use({
      extensions: [embedExtension, wikilinkExtension, emojiExtension, superscriptExtension, subscriptExtension, highlightExtension],
      renderer: {
        heading({ tokens, depth }) {
          const text = this.parser.parseInline(tokens)
          const raw = text.replace(/<[^>]+>/g, "")
          const slug = generateHeadingSlug(raw, controller._headingSlugCounts)
          return `<h${depth} id="${slug}">${text}</h${depth}>\n`
        }
      }
    })
    marked.setOptions({ gfm: true, breaks: false })

    this._debounceTimer = null
    this._scrollSyncEnabled = true
    this._isScrolling = false
    this._scrollCooldown = null
    this._wikilinkState = new Map()
    this._embedCache = new Map()
    this._maxEmbedDepth = 3
    this._renderVersion = 0
    this._scrollSource = null
    this.lastScrollTarget = null
    this.scrollThreshold = 12
  }

  disconnect() {
    clearTimeout(this._debounceTimer)
  }

  // Called by editor when content changes
  update(content) {
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this._render(content), 150)
  }

  // Set scroll position from ratio (0-1)
  setScrollRatio(ratio) {
    if (this._isScrolling) return
    if (this._scrollSource === "editor-typewriter") return
    const el = this._scrollContainer()
    const max = el.scrollHeight - el.clientHeight
    if (max > 0) el.scrollTop = max * ratio
  }

  getScrollRatio() {
    const el = this._scrollContainer()
    const max = el.scrollHeight - el.clientHeight
    return max > 0 ? el.scrollTop / max : 0
  }

  _scrollContainer() {
    return this.element.querySelector(".preview-prose-wrapper") || this.element
  }

  // Handle preview scroll → sync back to editor
  scroll() {
    if (this._isScrolling) return
    if (this._scrollSource === "editor-typewriter") return
    this._isScrolling = true

    this.dispatch("scroll", {
      detail: { ratio: this.getScrollRatio() },
      bubbles: true
    })

    clearTimeout(this._scrollCooldown)
    this._scrollCooldown = setTimeout(() => { this._isScrolling = false }, 400)
  }

  setTypewriterMode(enabled) {
    this.outputTarget.classList.toggle("preview-typewriter-mode", enabled)
    if (!enabled) {
      this._scrollSource = null
      this.lastScrollTarget = null
    }
  }

  syncToTypewriter(currentLine, totalLines) {
    if (!this.hasOutputTarget || totalLines <= 1) return
    if (this._scrollSource === "preview") return

    this._scrollSource = "editor-typewriter"

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const container = this._scrollContainer()
        const lineRatio = Math.max(0, Math.min(1, (currentLine - 1) / (totalLines - 1)))
        const style = window.getComputedStyle(this.outputTarget)
        const paddingBottom = parseFloat(style.paddingBottom) || 0
        const actualContentHeight = Math.max(0, this.outputTarget.scrollHeight - paddingBottom)
        const contentPosition = lineRatio * actualContentHeight
        const targetY = container.clientHeight * 0.5
        const desiredScroll = Math.max(0, contentPosition - targetY)

        if (this.lastScrollTarget == null || Math.abs(desiredScroll - this.lastScrollTarget) > this.scrollThreshold) {
          this.lastScrollTarget = desiredScroll
          container.scrollTo({ top: desiredScroll, behavior: "smooth" })
        }

        clearTimeout(this._scrollCooldown)
        this._scrollCooldown = setTimeout(() => {
          this._scrollSource = null
        }, 250)
      })
    })
  }

  _render(content) {
    try {
      const renderVersion = ++this._renderVersion
      this._headingSlugCounts = new Map()
      const html = marked.parse(content || "")
      this.outputTarget.innerHTML = html
      // Syntax highlight code blocks if available
      this._highlightCode()
      this._stripBlockMarkers()
      this._validateWikilinks(renderVersion)
      this._loadEmbeds(renderVersion, 0)
    } catch (e) {
      console.error("Preview render error:", e)
    }
  }

  _highlightCode() {
    // Basic code block styling — no external dep needed
    this.outputTarget.querySelectorAll("pre code").forEach(el => {
      el.classList.add("cm-code-block")
    })
  }

  _stripBlockMarkers() {
    this.outputTarget.querySelectorAll("p, li, h1, h2, h3, h4, h5, h6, blockquote").forEach(el => {
      const match = el.innerHTML.match(/\s\^([a-zA-Z0-9-]+)\s*$/)
      if (match) {
        el.id = match[1]
        el.innerHTML = el.innerHTML.replace(/\s\^[a-zA-Z0-9-]+\s*$/, "")
      }
    })
  }

  async _validateWikilinks(renderVersion) {
    const links = Array.from(this.outputTarget.querySelectorAll("a.wikilink[data-uuid]"))
    if (links.length === 0) return

    const pendingChecks = []

    links.forEach(link => {
      const uuid = link.dataset.uuid
      if (!uuid) return

      const cachedState = this._wikilinkState.get(uuid)

      if (cachedState === false) {
        this._replaceBrokenWikilink(link)
        return
      }

      if (cachedState?.ok) {
        if (cachedState.href) {
          const base = cachedState.href.split("#")[0]
          const frag = link.dataset.headingSlug || link.dataset.blockId
          link.href = frag ? `${base}#${frag}` : cachedState.href
        }
        return
      }

      pendingChecks.push(this._checkWikilink(uuid, renderVersion))
    })

    if (pendingChecks.length > 0) {
      await Promise.allSettled(pendingChecks)
    }

    if (renderVersion !== this._renderVersion) return

    this.outputTarget.querySelectorAll("a.wikilink[data-uuid]").forEach(link => {
      const cachedState = this._wikilinkState.get(link.dataset.uuid)
      if (cachedState === false) {
        this._replaceBrokenWikilink(link)
      } else if (cachedState?.ok && cachedState.href) {
        const base = cachedState.href.split("#")[0]
        const frag = link.dataset.headingSlug || link.dataset.blockId
        link.href = frag ? `${base}#${frag}` : cachedState.href
      }
    })
  }

  async _checkWikilink(uuid, renderVersion) {
    try {
      const response = await fetch(`/notes/${uuid}`, {
        method: "GET",
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })

      if (renderVersion !== this._renderVersion) return
      if (response.ok) {
        this._wikilinkState.set(uuid, { ok: true, href: this._canonicalHref(response) })
        return
      }

      if (response.status === 404) {
        this._wikilinkState.set(uuid, false)
        return
      }

      this._wikilinkState.delete(uuid)
    } catch (error) {
      if (renderVersion !== this._renderVersion) return
      this._wikilinkState.delete(uuid)
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

  _replaceBrokenWikilink(link) {
    const broken = document.createElement("span")
    broken.className = "wikilink-broken"
    broken.textContent = link.textContent || ""
    broken.title = "Nota nao encontrada"
    link.replaceWith(broken)
  }

  async _loadEmbeds(renderVersion, depth) {
    if (depth >= this._maxEmbedDepth) {
      this._convertEmbedsToLinks()
      return
    }

    const containers = Array.from(
      this.outputTarget.querySelectorAll(".embed-container.embed-loading")
    )
    if (containers.length === 0) return

    const fetches = containers.map(container =>
      this._fetchEmbed(container, renderVersion)
    )
    await Promise.allSettled(fetches)

    if (renderVersion !== this._renderVersion) return
    this._loadEmbeds(renderVersion, depth + 1)
  }

  async _fetchEmbed(container, renderVersion) {
    const uuid = container.dataset.embedUuid
    const heading = container.dataset.embedHeading
    const block = container.dataset.embedBlock

    const cacheKey = `${uuid}:${heading || ""}:${block || ""}`
    const cached = this._embedCache.get(cacheKey)

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

        if (renderVersion !== this._renderVersion) return
        if (!response.ok) {
          this._markEmbedBroken(container)
          return
        }

        data = await response.json()
        if (!data.found) {
          this._markEmbedBroken(container)
          return
        }

        this._embedCache.set(cacheKey, data)
      } catch (_) {
        this._markEmbedBroken(container)
        return
      }
    }

    const savedCounts = this._headingSlugCounts
    this._headingSlugCounts = new Map()
    const html = marked.parse(data.markdown || "")
    this._headingSlugCounts = savedCounts

    const contentEl = container.querySelector(".embed-content")
    contentEl.innerHTML = html

    const headerEl = container.querySelector(".embed-header")
    headerEl.innerHTML = `<a href="/notes/${data.note_slug}" class="embed-source-link">${data.note_title}</a>`

    container.classList.remove("embed-loading")
    container.classList.add("embed-loaded")

    // Strip block markers within embed content
    contentEl.querySelectorAll("p, li, h1, h2, h3, h4, h5, h6, blockquote").forEach(el => {
      const match = el.innerHTML.match(/\s\^([a-zA-Z0-9-]+)\s*$/)
      if (match) {
        el.id = match[1]
        el.innerHTML = el.innerHTML.replace(/\s\^[a-zA-Z0-9-]+\s*$/, "")
      }
    })
  }

  _markEmbedBroken(container) {
    container.classList.remove("embed-loading")
    container.classList.add("embed-broken")
    const contentEl = container.querySelector(".embed-content")
    contentEl.innerHTML = '<span class="embed-error">Conteudo nao encontrado</span>'
  }

  _convertEmbedsToLinks() {
    this.outputTarget.querySelectorAll(".embed-container.embed-loading").forEach(container => {
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
