import { Controller } from "@hotwired/stimulus"

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
    "dialogOverlay", "spinner",
    "generateTab", "libraryTab", "generatePanel", "libraryPanel", "libraryList",
    "karaokePanel", "karaokeContainer", "karaokeToggle", "playerInfo",
    "staleNotice"
  ]

  connect() {
    this._providers = []
    this._voices = {}
    this._activeAsset = null
    this._staleAudio = null
    this._headRevisionId = null
    this._polling = null
    this._boundKeydown = this._onKeydown.bind(this)
    this._boundEditorChange = this._onEditorChange.bind(this)
    document.addEventListener("keydown", this._boundKeydown)
    this.element.addEventListener("codemirror:change", this._boundEditorChange)
    this.fetchStatus()
  }

  disconnect() {
    this.stopPolling()
    document.removeEventListener("keydown", this._boundKeydown)
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
    this.populateDialog()
    this.switchToGenerate()
    this.dialogTarget.classList.remove("hidden")
    if (this.hasDialogOverlayTarget) this.dialogOverlayTarget.classList.remove("hidden")
  }

  closeDialog() {
    if (this.hasDialogTarget) this.dialogTarget.classList.add("hidden")
    if (this.hasDialogOverlayTarget) this.dialogOverlayTarget.classList.add("hidden")
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

    const audioEl = asset.ready && asset.audio_url
      ? `<audio controls preload="none" class="w-full h-7 mt-1" style="max-height: 28px;" src="${this._escapeAttr(asset.audio_url)}"></audio>`
      : asset.pending
        ? `<p class="text-[10px] mt-1" style="color: var(--theme-accent);">Gerando...</p>`
        : ""

    const activateBtn = asset.ready && !isActive
      ? `<button class="text-[10px] px-2 py-0.5 rounded mt-1" style="background: var(--theme-accent); color: white;" data-action="click->tts#activateAsset" data-asset-id="${this._escapeAttr(asset.id)}" data-audio-url="${this._escapeAttr(asset.audio_url)}">Usar</button>`
      : isActive
        ? `<span class="text-[10px] px-2 py-0.5 rounded mt-1 inline-block" style="background: var(--theme-accent-dim, rgba(99,102,241,0.2)); color: var(--theme-accent);">Ativo</span>`
        : ""

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
          ${activateBtn}
        </div>
        ${audioEl}
      </div>
    `
  }

  activateAsset(event) {
    const btn = event.currentTarget
    const audioUrl = btn.dataset.audioUrl
    const assetId = btn.dataset.assetId
    if (!audioUrl) return

    this._activeAsset = { id: assetId, audio_url: audioUrl, ready: true }
    this.showPlayer(audioUrl)
    this.closeDialog()
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
    const text = this._getEditorText()

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

    // Update player info with asset metadata
    this._updatePlayerInfo()
    this._updateKaraoke()
  }

  hidePlayer() {
    if (this.hasPlayerTarget) this.playerTarget.classList.add("hidden")
    if (this.hasAudioTarget) this.audioTarget.src = ""
    if (this.hasKaraokePanelTarget) this.karaokePanelTarget.classList.add("hidden")
  }

  showGenerateButton() {
    if (this.hasGenerateBtnTarget) this.generateBtnTarget.classList.remove("hidden")
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    if (this.hasPlayerTarget) this.playerTarget.classList.add("hidden")
    if (this.hasStatusLabelTarget) this.statusLabelTarget.textContent = ""
  }

  // ── Karaoke ────────────────────────────────────────

  toggleKaraoke() {
    if (!this.hasKaraokePanelTarget) return

    const isHidden = this.karaokePanelTarget.classList.contains("hidden")
    if (isHidden) {
      this.karaokePanelTarget.classList.remove("hidden")
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.style.color = "var(--theme-accent)"
      }
    } else {
      this.karaokePanelTarget.classList.add("hidden")
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.style.color = "var(--theme-text-muted)"
      }
    }
  }

  _updateKaraoke() {
    if (!this.hasKaraokeContainerTarget || !this._activeAsset) return

    const karaokeCtrl = this.application.getControllerForElementAndIdentifier(
      this.karaokeContainerTarget, "karaoke"
    )

    const alignment = this._activeAsset.alignment_data
    if (alignment && alignment.words && alignment.words.length > 0) {
      // Use Stimulus value setter to trigger alignmentValueChanged()
      if (karaokeCtrl) {
        karaokeCtrl.alignmentValue = alignment
      }
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.classList.remove("hidden")
      }
    } else {
      if (karaokeCtrl) {
        karaokeCtrl.alignmentValue = {}
      }
      if (this.hasKaraokeToggleTarget) {
        this.karaokeToggleTarget.classList.add("hidden")
      }
      if (this.hasKaraokePanelTarget) this.karaokePanelTarget.classList.add("hidden")
    }
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
        this.stopPolling()
        this._activeAsset = data
        this.showPlayer(data.audio_url)
        this.showFlashSuccess("Audio pronto!")
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

  // ── Helpers ─────────────────────────────────────────

  _getEditorText() {
    const editorPane = this.element.querySelector('[data-controller~="codemirror"]')
    const cmController = editorPane &&
      this.application.getControllerForElementAndIdentifier(editorPane, "codemirror")
    if (!cmController) return ""

    // Prefer selected text if available
    const selection = cmController.getSelection?.()
    if (selection && selection.trim()) return selection

    return cmController.getValue?.() || ""
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
    // Ctrl+Shift+T — toggle TTS dialog
    if (event.ctrlKey && event.shiftKey && event.key === "T") {
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
