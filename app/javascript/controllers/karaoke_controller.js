import { Controller } from "@hotwired/stimulus"

// Karaoke controller — highlights words in the preview pane in sync with TTS audio.
// Injects <span class="karaoke-word"> around each word in the preview's text nodes,
// paired 1:1 with MFA alignment timing data.
export default class extends Controller {
  static values = {
    alignment: { type: Object, default: {} }
  }

  initialize() {
    this._currentIndex = -1
    this._words = []
    this._spans = []
    this._injected = false
    this._boundTimeUpdate = this._onTimeUpdate.bind(this)
  }

  connect() {
  }

  disconnect() {
    this.deactivate()
  }

  alignmentValueChanged() {
    const newWords = this.alignmentValue?.words || []
    // Guard against Stimulus double-fire (setter + MutationObserver):
    // only deactivate if the alignment data actually changed.
    if (this._injected && JSON.stringify(newWords) !== JSON.stringify(this._words)) {
      this.deactivate()
    }
    this._words = newWords
  }

  // Called by tts_controller when audio starts playing and alignment is ready
  activate() {
    if (this._injected || this._words.length === 0) return
    const preview = this._previewElement()

    // Preview might not have rendered yet on initial page load — retry until it has content
    if (!preview || !preview.textContent?.trim()) {
      if (!this._retryCount) this._retryCount = 0
      if (this._retryCount < 10) {
        this._retryCount++
        setTimeout(() => this.activate(), 300)
      }
      return
    }
    this._retryCount = 0

    this._injectSpans()
    this._bindAudio()
    this._watchPreview()
    this._injected = true
  }

  // Called when audio stops, editor changes, or note changes
  deactivate() {
    this._unwatchPreview()
    this._unbindAudio()
    this._cleanupSpans()
    this._currentIndex = -1
    this._injected = false
  }

  get isActive() { return this._injected }

  // ── Inject karaoke spans into preview DOM ────────────

  _injectSpans() {
    const preview = this._previewElement()
    if (!preview) return

    this._spans = []
    let wordIndex = 0

    // Collect text nodes in DOM order (skip code blocks)
    const textNodes = []
    const walker = document.createTreeWalker(preview, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const el = node.parentElement
        if (!el) return NodeFilter.FILTER_REJECT
        const tag = el.tagName
        if (tag === "CODE" || tag === "PRE" || tag === "SCRIPT" || tag === "STYLE")
          return NodeFilter.FILTER_REJECT
        if (!node.textContent.trim()) return NodeFilter.FILTER_REJECT
        return NodeFilter.FILTER_ACCEPT
      }
    })
    while (walker.nextNode()) textNodes.push(walker.currentNode)

    for (const textNode of textNodes) {
      if (wordIndex >= this._words.length) break

      const parts = textNode.textContent.split(/(\s+)/)
      const fragment = document.createDocumentFragment()

      for (const part of parts) {
        if (!part) continue

        // Whitespace — keep as-is
        if (/^\s+$/.test(part)) {
          fragment.appendChild(document.createTextNode(part))
          continue
        }

        // Word — wrap in karaoke span if we still have alignment data
        if (wordIndex < this._words.length) {
          const w = this._words[wordIndex]
          const span = document.createElement("span")
          span.className = "karaoke-word"
          span.dataset.index = wordIndex
          span.dataset.start = w.start
          span.dataset.end = w.end
          span.textContent = part
          span.addEventListener("click", this._onWordClick.bind(this))
          this._spans.push(span)
          fragment.appendChild(span)
          wordIndex++
        } else {
          fragment.appendChild(document.createTextNode(part))
        }
      }

      textNode.parentNode.replaceChild(fragment, textNode)
    }
  }

  _cleanupSpans() {
    for (const span of this._spans) {
      if (span.parentNode) {
        span.replaceWith(document.createTextNode(span.textContent))
      }
    }
    this._spans = []

    // Merge adjacent text nodes back together
    const preview = this._previewElement()
    if (preview) preview.normalize()
  }

  // ── Preview re-render watcher ───────────────────────
  // The preview pane may re-render (innerHTML replacement) after karaoke spans
  // are injected, destroying them. Watch for this and re-inject.

  _watchPreview() {
    this._unwatchPreview()
    const preview = this._previewElement()
    if (!preview) return

    this._previewObserver = new MutationObserver(() => {
      // If our spans were destroyed by a preview re-render, re-inject.
      // Use isConnected (not parentNode) because detached subtrees still have parents.
      if (this._injected && this._spans.length > 0 && !this._spans[0].isConnected) {
        this._spans = []
        this._injected = false
        this._currentIndex = -1
        this.activate()
      }
    })
    this._previewObserver.observe(preview, { childList: true, subtree: true })
  }

  _unwatchPreview() {
    if (this._previewObserver) {
      this._previewObserver.disconnect()
      this._previewObserver = null
    }
  }

  // ── Audio sync ───────────────────────────────────────

  _bindAudio() {
    const audio = this._audioElement()
    if (audio) audio.addEventListener("timeupdate", this._boundTimeUpdate)
  }

  _unbindAudio() {
    const audio = this._audioElement()
    if (audio) audio.removeEventListener("timeupdate", this._boundTimeUpdate)
  }

  _onTimeUpdate() {
    const audio = this._audioElement()
    if (!audio || this._spans.length === 0) return

    const t = audio.currentTime
    const idx = this._findWordIndex(t)

    if (idx !== this._currentIndex) {
      this._highlightWord(idx)
      this._currentIndex = idx
    }
  }

  _findWordIndex(time) {
    const words = this._words
    if (words.length === 0) return -1

    let lo = 0, hi = words.length - 1
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (time < words[mid].start) hi = mid - 1
      else if (time >= words[mid].end) lo = mid + 1
      else return mid
    }
    return -1
  }

  _highlightWord(index) {
    this._spans.forEach((span, i) => {
      if (i === index) {
        span.classList.add("karaoke-active")
        span.scrollIntoView({ behavior: "smooth", block: "nearest" })
      } else {
        span.classList.remove("karaoke-active")
      }
    })
  }

  // ── Click to seek ────────────────────────────────────

  _onWordClick(event) {
    const span = event.currentTarget
    const start = parseFloat(span.dataset.start)
    const audio = this._audioElement()
    if (audio && !isNaN(start)) {
      audio.currentTime = start
      if (audio.paused) audio.play()
    }
  }

  // ── Element references ───────────────────────────────

  _previewElement() {
    return this.element.closest("[data-controller~='tts']")
      ?.querySelector('[data-preview-target="output"]')
  }

  _audioElement() {
    return this.element.closest("[data-controller~='tts']")
      ?.querySelector("audio[data-tts-target='audio']")
  }
}
