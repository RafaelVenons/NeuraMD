import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension, wikilinkExtension } from "lib/marked_extensions"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    marked.use({ extensions: [wikilinkExtension, emojiExtension, superscriptExtension, subscriptExtension, highlightExtension] })
    marked.setOptions({ gfm: true, breaks: false })

    this._debounceTimer = null
    this._scrollSyncEnabled = true
    this._isScrolling = false
    this._scrollCooldown = null
    this._wikilinkState = new Map()
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
      const html = marked.parse(content || "")
      this.outputTarget.innerHTML = html
      // Syntax highlight code blocks if available
      this._highlightCode()
      this._validateWikilinks(renderVersion)
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
        if (cachedState.href) link.href = cachedState.href
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
        link.href = cachedState.href
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
}
