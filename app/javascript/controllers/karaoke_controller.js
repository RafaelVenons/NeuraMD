import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    alignment: { type: Object, default: {} }
  }

  static targets = ["text", "audio"]

  connect() {
    this._currentIndex = -1
    this._words = []
    this._boundTimeUpdate = this._onTimeUpdate.bind(this)
    this._render()
    this._bindAudio()
  }

  disconnect() {
    this._unbindAudio()
  }

  alignmentValueChanged() {
    this._currentIndex = -1
    this._unbindAudio()
    this._render()
    this._bindAudio()
  }

  // ── Rendering ────────────────────────────────────

  _render() {
    if (!this.hasTextTarget) return
    const words = this.alignmentValue?.words || []
    this._words = words

    if (words.length === 0) {
      this.textTarget.innerHTML = `<p class="text-xs" style="color: var(--theme-text-muted);">Nenhum alinhamento disponivel.</p>`
      return
    }

    this.textTarget.innerHTML = words.map((w, i) =>
      `<span class="karaoke-word" data-index="${i}" data-start="${w.start}" data-end="${w.end}" data-action="click->karaoke#seekToWord">${this._escapeHtml(w.word)}</span>`
    ).join(" ")
  }

  // ── Audio sync ───────────────────────────────────

  _bindAudio() {
    const audio = this._audioElement()
    if (audio) {
      audio.addEventListener("timeupdate", this._boundTimeUpdate)
    }
  }

  _unbindAudio() {
    const audio = this._audioElement()
    if (audio) {
      audio.removeEventListener("timeupdate", this._boundTimeUpdate)
    }
  }

  _onTimeUpdate() {
    const audio = this._audioElement()
    if (!audio || this._words.length === 0) return

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

    // Binary search for the word containing `time`
    let lo = 0, hi = words.length - 1
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (time < words[mid].start) {
        hi = mid - 1
      } else if (time >= words[mid].end) {
        lo = mid + 1
      } else {
        return mid
      }
    }
    return -1
  }

  _highlightWord(index) {
    if (!this.hasTextTarget) return
    const spans = this.textTarget.querySelectorAll(".karaoke-word")

    spans.forEach((span, i) => {
      if (i === index) {
        span.classList.add("karaoke-active")
        // Auto-scroll to keep active word visible
        span.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" })
      } else {
        span.classList.remove("karaoke-active")
      }
    })
  }

  // ── Seek on click ────────────────────────────────

  seekToWord(event) {
    const span = event.currentTarget
    const start = parseFloat(span.dataset.start)
    const audio = this._audioElement()
    if (audio && !isNaN(start)) {
      audio.currentTime = start
      if (audio.paused) audio.play()
    }
  }

  // ── Helpers ──────────────────────────────────────

  _audioElement() {
    if (this.hasAudioTarget) return this.audioTarget
    // Fall back: find audio in parent tts controller
    return this.element.closest("[data-controller~='tts']")?.querySelector("audio[data-tts-target='audio']")
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }
}
