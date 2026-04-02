import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension, wikilinkExtension, embedExtension } from "lib/marked_extensions"
import { generateHeadingSlug } from "lib/heading_slug"
import { WikilinkValidator } from "lib/preview/wikilink_validator"
import { EmbedLoader } from "lib/preview/embed_loader"

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
    this._renderVersion = 0
    this._scrollSource = null
    this.lastScrollTarget = null
    this.scrollThreshold = 12

    this._wikilinkValidator = new WikilinkValidator()
    this._embedLoader = new EmbedLoader(3)
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
      this._highlightCode()
      this._stripBlockMarkers(this.outputTarget)
      const isStale = () => renderVersion !== this._renderVersion
      this._wikilinkValidator.validate(this.outputTarget, renderVersion, isStale)
      this._embedLoader.load(this.outputTarget, renderVersion, isStale, (md) => {
        const saved = this._headingSlugCounts
        this._headingSlugCounts = new Map()
        const result = marked.parse(md)
        this._headingSlugCounts = saved
        return result
      }, (el) => this._stripBlockMarkers(el))
    } catch (e) {
      console.error("Preview render error:", e)
    }
  }

  _highlightCode() {
    this.outputTarget.querySelectorAll("pre code").forEach(el => {
      el.classList.add("cm-code-block")
    })
  }

  _stripBlockMarkers(container) {
    container.querySelectorAll("p, li, h1, h2, h3, h4, h5, h6, blockquote").forEach(el => {
      const match = el.innerHTML.match(/\s\^([a-zA-Z0-9-]+)\s*$/)
      if (match) {
        el.id = match[1]
        el.innerHTML = el.innerHTML.replace(/\s\^[a-zA-Z0-9-]+\s*$/, "")
      }
    })
  }
}
