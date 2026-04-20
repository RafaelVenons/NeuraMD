import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension, wikilinkExtension, mathBlockExtension, mathInlineExtension } from "lib/marked_extensions"
import { generateHeadingSlug } from "lib/heading_slug"
import { WikilinkValidator } from "lib/preview/wikilink_validator"
import { RenderPipeline } from "lib/preview/render_pipeline"
import { highlightCodeRenderer } from "lib/preview/renderers/highlight_code"
import { stripBlockMarkersRenderer } from "lib/preview/renderers/strip_block_markers"
import { createWikilinkRenderer } from "lib/preview/renderers/wikilink_renderer"
import { mediaEmbedRenderer } from "lib/preview/renderers/media_embed"
import { mermaidRenderer } from "lib/preview/renderers/mermaid_renderer"
import { katexRenderer } from "lib/preview/renderers/katex_renderer"
import { chartRenderer } from "lib/preview/renderers/chart_renderer"
import { RenderGuards } from "lib/preview/render_guards"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this._headingSlugCounts = new Map()
    const controller = this
    marked.use({
      extensions: [wikilinkExtension, mathBlockExtension, mathInlineExtension, emojiExtension, superscriptExtension, subscriptExtension, highlightExtension],
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

    this._guards = new RenderGuards()
    this._pipeline = new RenderPipeline(this._guards)
    this._pipeline.register(highlightCodeRenderer)
    this._pipeline.register(stripBlockMarkersRenderer)
    this._pipeline.register(createWikilinkRenderer(this._wikilinkValidator))
    this._pipeline.register(mediaEmbedRenderer)
    this._pipeline.register(mermaidRenderer)
    this._pipeline.register(katexRenderer)
    this._pipeline.register(chartRenderer)
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

      const isStale = () => renderVersion !== this._renderVersion
      const context = {
        renderVersion,
        isStale,
        outputElement: this.outputTarget,
        guards: this._guards,
        parseMarkdown: (md) => {
          const saved = this._headingSlugCounts
          this._headingSlugCounts = new Map()
          const result = marked.parse(md)
          this._headingSlugCounts = saved
          return result
        },
        stripBlockMarkers: (el) => {
          el.querySelectorAll("p, li, h1, h2, h3, h4, h5, h6, blockquote").forEach(node => {
            const match = node.innerHTML.match(/\s\^([a-zA-Z0-9-]+)\s*$/)
            if (match) {
              node.id = match[1]
              node.innerHTML = node.innerHTML.replace(/\s\^[a-zA-Z0-9-]+\s*$/, "")
            }
          })
        }
      }

      this._pipeline.run(this.outputTarget, context)
    } catch (e) {
      console.error("Preview render error:", e)
    }
  }

}
