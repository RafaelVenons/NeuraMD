import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

export default class extends Controller {
  static values = {
    statusUrl: String,
    generateUrl: String,
    showUrl: String,
    rejectUrl: String,
    audioUrl: String,
    libraryUrl: String,
    noteLanguage: { type: String, default: "pt-BR" }
  }

  static targets = [
    "generateBtn", "dialog", "player", "audio", "statusLabel",
    "providerSelect", "voiceSelect", "languageSelect", "formatSelect",
    "dropdownWrapper", "spinner",
    "generateTab", "libraryTab", "generatePanel", "libraryPanel", "libraryList",
    "karaokeContainer", "karaokeToggle", "playerInfo",
    "staleNotice"
  ]

  connect() {
    this._providers = []
    this._voices = {}
    this._activeAsset = null
    this._staleAudio = null
    this._headRevisionId = null
    this._polling = null
    this._dialogOpen = false
    // Capture autoplay flag from sessionStorage (set by library card click)
    this._wantsAutoplay = sessionStorage.getItem("tts-autoplay") === "1"
    if (this._wantsAutoplay) sessionStorage.removeItem("tts-autoplay")
    this._boundKeydown = this._onKeydown.bind(this)
    this._boundEditorChange = this._onEditorChange.bind(this)
    this._boundClickOutside = (e) => {
      if (this.hasDropdownWrapperTarget && !this.dropdownWrapperTarget.contains(e.target)) {
        this.closeDialog()
      }
    }
    document.addEventListener("keydown", this._boundKeydown)
    this.element.addEventListener("codemirror:change", this._boundEditorChange)
    this.fetchStatus()
  }

  disconnect() {
    this.stopPolling()
    document.removeEventListener("keydown", this._boundKeydown)
    document.removeEventListener("click", this._boundClickOutside)
    this.element.removeEventListener("codemirror:change", this._boundEditorChange)
  }

  // ── Shell hydration (note navigation) ──────────────

  hydrateNoteContext(payload) {
    // Stop any ongoing polling/playback for the previous note
    this.stopPolling()
    this._activeAsset = null
    this._staleAudio = null
    this.hidePlayer()
    this._hideStaleNotice()

    // Update URLs from the new note's payload
    const slug = payload.note?.slug
    if (slug) {
      this.statusUrlValue = `/notes/${slug}/tts_status`
      this.generateUrlValue = `/notes/${slug}/tts_generate`
      this.showUrlValue = `/notes/${slug}/tts_show`
      this.rejectUrlValue = `/notes/${slug}/tts_reject`
      this.audioUrlValue = `/notes/${slug}/tts_audio`
      this.libraryUrlValue = `/notes/${slug}/tts_library`
      this.noteLanguageValue = payload.note?.detected_language || "pt-BR"
    }

    // Fetch status for the new note
    this.fetchStatus()
  }

  // ── Data fetching ───────────────────────────────────

  async fetchStatus() {
    try {
      const res = await fetch(this.statusUrlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) return

      const data = await res.json()
      this._providers = data.providers || []
      this._voices = data.voices || {}
      this._activeAsset = data.active_asset
      this._headRevisionId = data.head_revision_id
      this._staleAudio = data.stale_audio || null

      this._hideStaleNotice()

      if (this._activeAsset?.ready) {
        this.showPlayer(this._activeAsset.audio_url)
        this._autoplayIfRequested()
        // If MFA alignment is still running, poll until it completes
        if (this._activeAsset.alignment_status === "pending") this.startPolling()
      } else if (this._activeAsset?.pending) {
        this.showGenerating()
        this.startPolling()
      } else if (this._staleAudio) {
        this._showStaleNotice()
        this.showGenerateButton()
      } else {
        this.showGenerateButton()
      }
    } catch (e) {
      console.warn("TTS status fetch failed:", e)
    }
  }

  // ── Dialog ──────────────────────────────────────────

  openDialog() {
    if (!this.hasDialogTarget) return
    if (this._dialogOpen) { this.closeDialog(); return }
    this.populateDialog()
    this.switchToGenerate()
    this.dialogTarget.classList.remove("hidden")
    this._dialogOpen = true
    setTimeout(() => document.addEventListener("click", this._boundClickOutside), 0)
  }

  closeDialog() {
    if (this.hasDialogTarget) this.dialogTarget.classList.add("hidden")
    this._dialogOpen = false
    document.removeEventListener("click", this._boundClickOutside)
  }

  populateDialog() {
    if (this.hasProviderSelectTarget) {
      this.providerSelectTarget.innerHTML = this._providers
        .map(p => `<option value="${p.name}">${p.label}</option>`).join("")
    }
    if (this.hasLanguageSelectTarget) {
      this.languageSelectTarget.value = this.noteLanguageValue || "pt-BR"
    }
    this.updateVoices()
  }

  // ── Tabs ──────────────────────────────────────────

  switchToGenerate() {
    if (this.hasGeneratePanelTarget) this.generatePanelTarget.classList.remove("hidden")
    if (this.hasLibraryPanelTarget) this.libraryPanelTarget.classList.add("hidden")
    if (this.hasGenerateTabTarget) {
      this.generateTabTarget.classList.add("border-[var(--theme-accent)]")
      this.generateTabTarget.classList.remove("border-transparent")
      this.generateTabTarget.style.color = "var(--theme-text-primary)"
    }
    if (this.hasLibraryTabTarget) {
      this.libraryTabTarget.classList.remove("border-[var(--theme-accent)]")
      this.libraryTabTarget.classList.add("border-transparent")
      this.libraryTabTarget.style.color = "var(--theme-text-muted)"
    }
  }

  switchToLibrary() {
    if (this.hasGeneratePanelTarget) this.generatePanelTarget.classList.add("hidden")
    if (this.hasLibraryPanelTarget) this.libraryPanelTarget.classList.remove("hidden")
    if (this.hasLibraryTabTarget) {
      this.libraryTabTarget.classList.add("border-[var(--theme-accent)]")
      this.libraryTabTarget.classList.remove("border-transparent")
      this.libraryTabTarget.style.color = "var(--theme-text-primary)"
    }
    if (this.hasGenerateTabTarget) {
      this.generateTabTarget.classList.remove("border-[var(--theme-accent)]")
      this.generateTabTarget.classList.add("border-transparent")
      this.generateTabTarget.style.color = "var(--theme-text-muted)"
    }
    this._loadLibrary()
  }

  async _loadLibrary() {
    if (!this.hasLibraryListTarget || !this.hasLibraryUrlValue) return

    this.libraryListTarget.innerHTML = `<p class="text-xs text-center py-4" style="color: var(--theme-text-muted);">Carregando...</p>`

    try {
      const res = await fetch(this.libraryUrlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) return

      const data = await res.json()
      const assets = data.assets || []

      if (assets.length === 0) {
        this.libraryListTarget.innerHTML = `<p class="text-xs text-center py-6" style="color: var(--theme-text-muted);">Nenhum audio gerado ainda.</p>`
        return
      }

      this.libraryListTarget.innerHTML = assets.map(a => this._libraryCard(a)).join("")
    } catch (e) {
      this.libraryListTarget.innerHTML = `<p class="text-xs text-center py-4 text-red-400">Erro ao carregar biblioteca.</p>`
    }
  }

  _libraryCard(asset) {
    const isActive = this._activeAsset?.id === asset.id
    const activeBorder = isActive ? "border-[var(--theme-accent)]" : "border-[var(--theme-border)]"
    const duration = asset.duration_ms ? `${(asset.duration_ms / 1000).toFixed(1)}s` : ""
    const created = asset.created_at ? new Date(asset.created_at).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : ""

    const statusBadge = asset.pending
      ? `<span class="text-[10px]" style="color: var(--theme-accent);">Gerando...</span>`
      : isActive
        ? `<span class="text-[10px] px-2 py-0.5 rounded inline-block" style="background: var(--theme-accent-dim, rgba(99,102,241,0.2)); color: var(--theme-accent);">Ativo</span>`
        : ""

    // Ready cards with a revision are clickable links to the revision page (autoplay)
    if (asset.ready && asset.revision_id) {
      const url = this._revisionUrl(asset.revision_id)
      return `
        <a href="${url}" class="block rounded-lg border ${activeBorder} p-2.5 cursor-pointer no-underline transition-colors"
           style="background: var(--theme-bg-tertiary); text-decoration: none;"
           data-action="click->tts#navigateToRevision" data-turbo-prefetch="false"
           onmouseover="this.style.background='var(--theme-bg-hover)'"
           onmouseout="this.style.background='var(--theme-bg-tertiary)'">
          <div class="flex items-center justify-between gap-2">
            <div class="flex flex-wrap gap-1">
              <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.provider)}</span>
              <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.voice)}</span>
              <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.language)}</span>
            </div>
            <span class="text-[10px] flex-shrink-0" style="color: var(--theme-text-faint);">${this._escapeHtml(created)}</span>
          </div>
          <div class="flex items-center justify-between mt-1">
            <span class="text-[10px]" style="color: var(--theme-text-muted);">${this._escapeHtml(asset.format)} ${duration ? `· ${this._escapeHtml(duration)}` : ""}</span>
            <span class="text-[10px] inline-flex items-center gap-1" style="color: var(--theme-accent);">
              <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>
              Ouvir
            </span>
          </div>
        </a>
      `
    }

    // Pending / non-ready cards are not clickable
    return `
      <div class="rounded-lg border ${activeBorder} p-2.5" style="background: var(--theme-bg-tertiary);">
        <div class="flex items-center justify-between gap-2">
          <div class="flex flex-wrap gap-1">
            <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.provider)}</span>
            <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.voice)}</span>
            <span class="inline-block rounded px-1.5 py-0.5 text-[10px]" style="background: var(--theme-bg-secondary); color: var(--theme-text-muted);">${this._escapeHtml(asset.language)}</span>
          </div>
          <span class="text-[10px] flex-shrink-0" style="color: var(--theme-text-faint);">${this._escapeHtml(created)}</span>
        </div>
        <div class="flex items-center justify-between mt-1">
          <span class="text-[10px]" style="color: var(--theme-text-muted);">${this._escapeHtml(asset.format)} ${duration ? `· ${this._escapeHtml(duration)}` : ""}</span>
          ${statusBadge}
        </div>
      </div>
    `
  }

  navigateToRevision(event) {
    sessionStorage.setItem("tts-autoplay", "1")
    this.closeDialog()
  }

  _revisionUrl(revisionId) {
    // Extract slug from libraryUrlValue: /notes/:slug/tts_library
    const match = this.libraryUrlValue.match(/\/notes\/([^/]+)\/tts_library/)
    const slug = match ? match[1] : ""
    return `/notes/${slug}/revisions/${revisionId}`
  }

  // ── Provider / Voice ──────────────────────────────

  providerChanged() {
    this.updateVoices()
  }

  languageChanged() {
    this._refreshVoicesForLanguage()
  }

  updateVoices() {
    if (!this.hasVoiceSelectTarget || !this.hasProviderSelectTarget) return
    const provider = this.providerSelectTarget.value
    const voices = this._voices[provider] || []
    this.voiceSelectTarget.innerHTML = voices
      .map(v => `<option value="${v}">${v}</option>`).join("")
  }

  async _refreshVoicesForLanguage() {
    if (!this.hasLanguageSelectTarget) return
    const lang = this.languageSelectTarget.value

    try {
      const res = await fetch(`${this.statusUrlValue}?language=${encodeURIComponent(lang)}`, {
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) return
      const data = await res.json()
      this._voices = data.voices || {}
      this.updateVoices()
    } catch (e) {
      // Fall back to current voices
    }
  }

  // ── Generate ────────────────────────────────────────

  async generate() {
    const text = this._getTextForTts()

    if (!text.trim()) {
      this.showFlash("Nenhum texto para gerar audio.")
      return
    }

    const params = {
      text: text,
      language: this.hasLanguageSelectTarget ? this.languageSelectTarget.value : this.noteLanguageValue,
      voice: this.hasVoiceSelectTarget ? this.voiceSelectTarget.value : "",
      provider: this.hasProviderSelectTarget ? this.providerSelectTarget.value : "",
      audio_format: this.hasFormatSelectTarget ? this.formatSelectTarget.value : "mp3"
    }

    this.closeDialog()
    this.showGenerating()

    try {
      const res = await fetch(this.generateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify(params)
      })

      const data = await res.json()
      if (!res.ok) {
        this.showFlash(data.error || "Erro ao gerar audio.")
        this.showGenerateButton()
        return
      }

      if (data.cached) {
        this.fetchStatus()
      } else {
        this.startPolling()
      }
    } catch (e) {
      console.error("TTS generate error:", e)
      this.showFlash("Erro ao gerar audio.")
      this.showGenerateButton()
    }
  }

  // ── Reject ──────────────────────────────────────────

  async reject() {
    if (!this._activeAsset) return

    try {
      const res = await fetch(this.rejectUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ tts_asset_id: this._activeAsset.id })
      })

      if (res.ok) {
        this._activeAsset = null
        this.hidePlayer()
        this.showGenerateButton()
      }
    } catch (e) {
      console.error("TTS reject error:", e)
    }
  }

  // ── UI state ────────────────────────────────────────

  showPlayer(audioUrl) {
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.classList.remove("hidden")
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")

    if (this.hasPlayerTarget) {
      this.playerTarget.classList.remove("hidden")
      if (this.hasAudioTarget) {
        this.audioTarget.src = audioUrl
      }
    }
    if (this.hasStatusLabelTarget) this.statusLabelTarget.textContent = ""

    this._updatePlayerInfo()
    this._updateKaraoke()
  }

  hidePlayer() {
    if (this.hasPlayerTarget) this.playerTarget.classList.add("hidden")
    if (this.hasAudioTarget) this.audioTarget.src = ""
    this._karaokeController()?.deactivate()
  }

  showGenerateButton() {
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.classList.remove("hidden")
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    if (this.hasPlayerTarget) this.playerTarget.classList.add("hidden")
    if (this.hasStatusLabelTarget) this.statusLabelTarget.textContent = ""
  }

  // ── Karaoke (preview highlighting) ─────────────────

  toggleKaraoke() {
    const karaokeCtrl = this._karaokeController()
    if (!karaokeCtrl) return

    if (karaokeCtrl.isActive) {
      karaokeCtrl.deactivate()
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.style.color = "var(--theme-text-muted)"
      }
    } else {
      karaokeCtrl.activate()
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.style.color = "var(--theme-accent)"
      }
    }
  }

  _updateKaraoke() {
    const karaokeCtrl = this._karaokeController()
    if (!karaokeCtrl || !this._activeAsset) return

    const alignment = this._activeAsset.alignment_data
    if (alignment && alignment.words && alignment.words.length > 0) {
      // Set words directly to avoid Stimulus MutationObserver double-fire
      karaokeCtrl._words = alignment.words
      karaokeCtrl.activate()
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.classList.remove("hidden")
        this.karaokeToggleTarget.style.color = "var(--theme-accent)"
      }
    } else {
      karaokeCtrl.deactivate()
      karaokeCtrl._words = []
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.classList.add("hidden")
      }
    }
  }

  _karaokeController() {
    if (!this.hasKaraokeContainerTarget) return null
    return this.application.getControllerForElementAndIdentifier(
      this.karaokeContainerTarget, "karaoke"
    )
  }

  _updatePlayerInfo() {
    if (!this.hasPlayerInfoTarget || !this._activeAsset) return
    const a = this._activeAsset
    const parts = [a.provider, a.voice, a.language].filter(Boolean)
    this.playerInfoTarget.textContent = parts.join(" · ")
  }

  showGenerating() {
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.classList.add("hidden")
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")
    if (this.hasStatusLabelTarget) this.statusLabelTarget.textContent = "Criando Audio..."
  }

  // ── Polling ─────────────────────────────────────────

  startPolling() {
    this.stopPolling()
    this._polling = setInterval(() => this.pollStatus(), 3000)
  }

  stopPolling() {
    if (this._polling) {
      clearInterval(this._polling)
      this._polling = null
    }
  }

  async pollStatus() {
    try {
      const res = await fetch(this.showUrlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) return

      const data = await res.json()
      if (data.ready && data.audio_url) {
        const wasReady = this._activeAsset?.ready
        this._activeAsset = data

        if (!wasReady) {
          // First time audio is ready — show player
          this.showPlayer(data.audio_url)
        } else {
          // Audio already playing — just refresh karaoke (MFA may have completed)
          this._updateKaraoke()
        }

        // Keep polling while MFA alignment is still running
        if (data.alignment_status === "pending") return

        this.stopPolling()
        if (!wasReady) this.showFlashSuccess("Audio pronto!")
      }
    } catch (e) {
      // Silently retry on next poll
    }
  }

  // ── Stale audio notice ─────────────────────────────

  _onEditorChange() {
    // If the current revision has audio and the user edits, show stale notice
    if (this._activeAsset?.ready && this._activeAsset?.revision_id) {
      this._staleAudio = {
        revision_id: this._activeAsset.revision_id,
        asset: this._activeAsset
      }
      this.hidePlayer()
      this._showStaleNotice()
      this._activeAsset = null
    }
  }

  _showStaleNotice() {
    if (!this.hasStaleNoticeTarget || !this._staleAudio) return
    this.staleNoticeTarget.classList.remove("hidden")
  }

  _hideStaleNotice() {
    if (this.hasStaleNoticeTarget) this.staleNoticeTarget.classList.add("hidden")
  }

  loadStaleAudio() {
    if (!this._staleAudio?.asset?.audio_url) return
    this._activeAsset = this._staleAudio.asset
    this._hideStaleNotice()
    this.showPlayer(this._staleAudio.asset.audio_url)
  }

  // ── Autoplay ────────────────────────────────────────

  _autoplayIfRequested() {
    if (!this._wantsAutoplay) return
    if (!this.hasAudioTarget) return
    this._wantsAutoplay = false

    const audio = this.audioTarget
    const tryPlay = () => {
      audio.play().catch(() => {
        // Browser may block autoplay without prior user gesture
      })
    }

    if (audio.readyState >= 2) {
      tryPlay()
    } else {
      audio.addEventListener("canplay", tryPlay, { once: true })
    }
  }

  // ── Helpers ─────────────────────────────────────────

  _getTextForTts() {
    const editorPane = this.element.querySelector('[data-controller~="codemirror"]')
    const cmController = editorPane &&
      this.application.getControllerForElementAndIdentifier(editorPane, "codemirror")

    // Prefer selected text if available — render it through marked first
    if (cmController) {
      const selection = cmController.getSelection?.()
      if (selection && selection.trim()) return this._markdownToPlaintext(selection)
    }

    // Full note: use the preview pane's rendered text (exact match with what user sees)
    const previewOutput = this.element.querySelector('[data-preview-target="output"]')
    if (previewOutput) return previewOutput.innerText || ""

    // Fallback: render editor content through marked
    if (cmController) {
      const raw = cmController.getValue?.() || ""
      return this._markdownToPlaintext(raw)
    }

    return ""
  }

  _markdownToPlaintext(markdown) {
    const tmp = document.createElement("div")
    tmp.innerHTML = marked.parse(markdown || "")
    return tmp.innerText || ""
  }

  // ── Speed control ────────────────────────────────

  changeSpeed(event) {
    if (!this.hasAudioTarget) return
    const speed = parseFloat(event.currentTarget.dataset.speed || "1")
    this.audioTarget.playbackRate = speed
    // Update visual state of speed buttons
    const buttons = this.element.querySelectorAll("[data-speed]")
    buttons.forEach(btn => {
      btn.style.color = parseFloat(btn.dataset.speed) === speed
        ? "var(--theme-accent)" : "var(--theme-text-muted)"
    })
  }

  // ── Keyboard shortcut ────────────────────────────

  _onKeydown(event) {
    // Ctrl+Shift+A — toggle TTS dialog (Audio)
    if (event.ctrlKey && event.shiftKey && event.key === "A") {
      event.preventDefault()
      if (this.hasDialogTarget && !this.dialogTarget.classList.contains("hidden")) {
        this.closeDialog()
      } else {
        this.openDialog()
      }
    }
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }

  _escapeAttr(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  showFlash(message) {
    const event = new CustomEvent("flash:show", {
      detail: { message, type: "error" },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  showFlashSuccess(message) {
    const event = new CustomEvent("flash:show", {
      detail: { message, type: "success" },
      bubbles: true
    })
    this.element.dispatchEvent(event)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
