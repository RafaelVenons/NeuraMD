import { Controller } from "@hotwired/stimulus"
import { computeWordDiff } from "lib/diff_utils"

export default class extends Controller {
  static targets = [
    "dialog",
    "configNotice",
    "diffContent",
    "historyDialog",
    "historyFilter",
    "historyList",
    "historyEmpty",
    "historyStatus",
    "modelSelect",
    "targetLanguageSelect",
    "originalText",
    "correctedText",
    "correctedDiff",
    "providerBadge",
    "editToggle",
    "acceptButton",
    "processingOverlay",
    "processingState",
    "processingProvider",
    "processingHint",
    "processingMeta",
    "processingError",
    "providerSelect",
    "scopeLabel",
    "selectorShell",
    "transportBadge"
  ]

  static values = {
    statusUrl: String,
    reviewUrl: String,
    historyUrl: String,
    requestUrlTemplate: String,
    cancelUrlTemplate: String,
    createTranslatedNoteUrlTemplate: String,
    noteTitle: String,
    noteLanguage: String
  }

  connect() {
    this.aiEnabled = false
    this.aiProvider = null
    this.aiModel = null
    this.providerOptions = []
    this.currentRequestId = null
    this.lastCompletedRequest = null
    this.pollTimer = null
    this.pollAttempt = 0
    this.pendingApplyMode = "document"
    this.pendingOriginalText = ""
    this.historyRequests = []
    this.historyFilter = "all"
    this.realtimeConnected = false
    this.streamObserver = null
    this._handleRequestUpdate = (event) => this._handleStreamRequestUpdate(event)
    this.element.addEventListener("ai-request:update", this._handleRequestUpdate)
    this._observeStreamSource()
    this.checkAvailability()
  }

  disconnect() {
    this.element.removeEventListener("ai-request:update", this._handleRequestUpdate)
    this.streamObserver?.disconnect()
    this._stopPolling()
  }

  openGrammar() {
    this.open("grammar_review")
  }

  openSuggest() {
    this.open("suggest")
  }

  openRewrite() {
    this.open("rewrite")
  }

  openTranslate() {
    this.open("translate")
  }

  async open(capability) {
    await this._cancelCurrentRequest()
    await this.checkAvailability()

    if (!this.aiEnabled) {
      this._showConfigNotice()
      return
    }

    const editor = this._editor()
    const documentMarkdown = editor.getValue()
    const selection = editor.getSelection()
    const targetLanguage = capability === "translate" ? this.selectedTargetLanguage() : null
    const text = capability === "translate" ? documentMarkdown : (selection || documentMarkdown)

    if (!text.trim()) {
      window.alert("Nenhum texto para processar.")
      return
    }

    this.pendingApplyMode = capability === "translate" ? "translation_note" : (selection ? "selection" : "document")
    this.pendingOriginalText = text
    this.lastCompletedRequest = null
    this.scopeLabelTarget.textContent =
      capability === "translate"
        ? `Tradução ${this.noteLanguageValue || "origem"} -> ${targetLanguage || "destino"}`
        : (selection ? "Trecho selecionado" : "Documento inteiro")

    this._showProcessing()

    try {
      const response = await fetch(this.reviewUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify({
          capability,
          provider: this.selectedProvider(),
          model: this.selectedModel(),
          target_language: targetLanguage,
          text,
          document_markdown: documentMarkdown
        })
      })

      const data = await response.json()
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao enfileirar processamento com IA.")

      this._startPolling(data.request_id)
      this.refreshHistory()
    } catch (error) {
      window.alert(error.message || "Falha ao processar com IA.")
      this._stopPolling()
    } finally {
    }
  }

  close() {
    this._cancelCurrentRequest()
    this.dialogTarget.close()
  }

  async openHistory() {
    this.historyDialogTarget.showModal()
    this._syncHistoryFilters()
    await this.refreshHistory()
  }

  closeHistory() {
    this.historyDialogTarget.close()
  }

  cancelProcessing() {
    this._cancelCurrentRequest({ hideOverlay: true })
  }

  async refreshHistory() {
    this.historyStatusTarget.textContent = "Carregando execuções recentes..."

    try {
      const response = await fetch(this.historyUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()

      if (!response.ok) throw new Error(data.error || "Falha ao carregar o histórico de IA.")

      this.historyRequests = data.requests || []
      this._renderHistory()
    } catch (error) {
      this.historyRequests = []
      this.historyListTarget.innerHTML = ""
      this.historyEmptyTarget.classList.add("hidden")
      this.historyStatusTarget.textContent = error.message || "Falha ao carregar o histórico de IA."
    }
  }

  selectHistoryFilter(event) {
    this.historyFilter = event.currentTarget.dataset.filterValue || "all"
    this._syncHistoryFilters()
    this._renderHistory()
  }

  async accept() {
    const editor = this._editor()
    const correctedText = this.correctedTextTarget.value

    if (this.pendingApplyMode === "translation_note") {
      try {
        await this._createTranslatedNote(correctedText)
      } catch (error) {
        window.alert(error.message || "Falha ao criar nota traduzida.")
      }
      return
    }

    if (this.pendingApplyMode === "selection") {
      editor.replaceSelection(correctedText)
    } else {
      editor.setValue(correctedText)
    }

    this.dispatch("accepted", {
      detail: {
        requestId: this.lastCompletedRequest?.id,
        capability: this.lastCompletedRequest?.capability,
        provider: this.lastCompletedRequest?.provider,
        model: this.lastCompletedRequest?.model
      },
      bubbles: true
    })

    editor.focus()
    this.close()
  }

  toggleEditMode() {
    const editing = !this.correctedTextTarget.classList.contains("hidden")

    if (editing) {
      this.correctedTextTarget.classList.add("hidden")
      this.correctedDiffTarget.classList.remove("hidden")
      this.editToggleTarget.textContent = "Editar"
    } else {
      this.correctedDiffTarget.classList.add("hidden")
      this.correctedTextTarget.classList.remove("hidden")
      this.correctedTextTarget.focus()
      this.editToggleTarget.textContent = "Ver diff"
    }
  }

  async checkAvailability() {
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()

      this.aiEnabled = !!data.enabled
      this.aiProvider = data.provider
      this.aiModel = data.model
      this.providerOptions = data.provider_options || []
      this._renderSelectors()
    } catch (_) {
      this.aiEnabled = false
      this.aiProvider = null
      this.aiModel = null
      this.providerOptions = []
      this._renderSelectors()
    }
  }

  providerChanged() {
    this._renderModelOptions(this.selectedProvider())
  }

  _showConfigNotice() {
    this.providerBadgeTarget.classList.add("hidden")
    this.configNoticeTarget.classList.remove("hidden")
    this.diffContentTarget.classList.add("hidden")
    this.dialogTarget.showModal()
  }

  _showDiff(original, corrected, provider, model) {
    const diff = computeWordDiff(original, corrected)
    this.configNoticeTarget.classList.add("hidden")
    this.diffContentTarget.classList.remove("hidden")
    this.diffContentTarget.classList.add("flex")
    this.originalTextTarget.innerHTML = this._renderDiff(diff, "original")
    this.correctedDiffTarget.innerHTML = this._renderDiff(diff, "corrected")
    this.correctedTextTarget.value = corrected
    this.correctedTextTarget.classList.add("hidden")
    this.correctedDiffTarget.classList.remove("hidden")
    this.editToggleTarget.textContent = "Editar"

    if (provider && model) {
      this.providerBadgeTarget.textContent = `${provider}: ${model}`
      this.providerBadgeTarget.classList.remove("hidden")
    } else {
      this.providerBadgeTarget.classList.add("hidden")
    }

    this.acceptButtonTarget.textContent =
      this.pendingApplyMode === "translation_note" ? "Criar nota traduzida" : "Aplicar"

    this.dialogTarget.showModal()
  }

  _showProcessing() {
    const provider = this.selectedProvider()
    const model = this.selectedModel()
    this.processingProviderTarget.textContent = provider && model ? `${provider}: ${model}` : "AI"
    this.processingStateTarget.textContent = "Na fila"
    this.processingHintTarget.textContent = provider === "ollama"
      ? "Job remoto no AIrch. Pode fechar e voltar depois."
      : "Processamento assíncrono em andamento."
    this.processingMetaTarget.textContent = "Aguardando execução..."
    this.processingErrorTarget.textContent = ""
    this.processingErrorTarget.classList.add("hidden")
    this.processingOverlayTarget.classList.remove("hidden")
  }

  _hideProcessing() {
    this.processingOverlayTarget.classList.add("hidden")
  }

  _startPolling(requestId) {
    this._stopPolling()
    this.currentRequestId = requestId
    this.pollAttempt = 0
    this._pollRequest(requestId)
  }

  async _pollRequest(requestId) {
    this.pollAttempt += 1

    try {
      const response = await fetch(this._requestUrl(requestId), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()

      if (!response.ok) throw new Error(data.error || "Falha ao consultar o status da IA.")

      if (data.provider && data.model) {
        this.processingProviderTarget.textContent = `${data.provider}: ${data.model}`
      } else if (data.provider) {
        this.processingProviderTarget.textContent = data.provider
      }

      this._updateProcessingState(data)

      if (data.status === "succeeded") {
        this.lastCompletedRequest = {
          id: data.id || requestId,
          capability: data.capability,
          provider: data.provider,
          model: data.model,
          targetLanguage: data.target_language || this.selectedTargetLanguage()
        }
        this._hideProcessing()
        this._showDiff(this.pendingOriginalText, data.corrected, data.provider, data.model)
        this._stopPolling()
        this.currentRequestId = null
        this.refreshHistory()
        return
      }

      if (data.status === "failed") {
        throw new Error(data.error || "Falha ao processar com IA.")
      }

      if (data.status === "canceled") {
        this._hideProcessing()
        this._stopPolling()
        this.currentRequestId = null
        this.refreshHistory()
        return
      }

      if (this.pollAttempt >= 60) {
        throw new Error("Tempo limite excedido aguardando a resposta da IA.")
      }

      this.pollTimer = window.setTimeout(
        () => this._pollRequest(requestId),
        this._pollDelayMs(data)
      )
    } catch (error) {
      this._hideProcessing()
      this._stopPolling()
      this.currentRequestId = null
      window.alert(error.message || "Falha ao processar com IA.")
    }
  }

  _stopPolling() {
    if (this.pollTimer) {
      window.clearTimeout(this.pollTimer)
      this.pollTimer = null
    }
  }

  async _cancelCurrentRequest({ hideOverlay = false } = {}) {
    const requestId = this.currentRequestId
    this._stopPolling()

    if (!requestId) {
      if (hideOverlay) this._hideProcessing()
      return
    }

    this.currentRequestId = null

    try {
      await fetch(this._cancelUrl(requestId), {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        }
      })
    } catch (_) {
    } finally {
      this.refreshHistory()
      if (hideOverlay) this._hideProcessing()
    }
  }

  _requestUrl(requestId) {
    return this.requestUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _cancelUrl(requestId) {
    return this.cancelUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _updateProcessingState(data) {
    const attemptsCount = Number(data.attempts_count || 0)
    const maxAttempts = Number(data.max_attempts || 0)

    if (data.status === "retrying") {
      this.processingStateTarget.textContent = "Tentando novamente"
      this.processingHintTarget.textContent = data.remote_hint || "Nova tentativa agendada."
      this.processingMetaTarget.textContent = this._joinMeta(
        this._retryMessage(data.next_retry_at, attemptsCount, maxAttempts),
        this._durationLabel(data)
      )
    } else if (data.status === "running") {
      this.processingStateTarget.textContent = "Processando"
      this.processingHintTarget.textContent = data.remote_hint || "Processamento assíncrono em andamento."
      this.processingMetaTarget.textContent = this._joinMeta(
        this._attemptLabel(attemptsCount, maxAttempts),
        this._durationLabel(data)
      )
    } else if (data.status === "queued") {
      this.processingStateTarget.textContent = "Na fila"
      this.processingHintTarget.textContent = data.remote_hint || "Aguardando execução na fila."
      this.processingMetaTarget.textContent = this._joinMeta(
        this._attemptLabel(attemptsCount, maxAttempts) || "Aguardando execução...",
        this._durationLabel(data)
      )
    } else {
      this.processingHintTarget.textContent = data.remote_hint || ""
      this.processingMetaTarget.textContent = this._durationLabel(data)
    }

    if (data.last_error_kind === "transient" && data.error) {
      this.processingErrorTarget.textContent = data.error
      this.processingErrorTarget.classList.remove("hidden")
    } else {
      this.processingErrorTarget.textContent = ""
      this.processingErrorTarget.classList.add("hidden")
    }
  }

  _handleStreamRequestUpdate(event) {
    const request = event.detail
    if (!request?.id) return

    this._upsertHistoryRequest(request)

    if (this.historyDialogTarget?.open) {
      this._renderHistory()
    }

    if (String(request.id) !== String(this.currentRequestId)) return

    this._stopPolling()

    if (request.provider && request.model) {
      this.processingProviderTarget.textContent = `${request.provider}: ${request.model}`
    } else if (request.provider) {
      this.processingProviderTarget.textContent = request.provider
    }

    this._updateProcessingState(request)

    if (request.status === "succeeded") {
      this.lastCompletedRequest = {
        id: request.id,
        capability: request.capability,
        provider: request.provider,
        model: request.model,
        targetLanguage: request.target_language || this.selectedTargetLanguage()
      }
      this._hideProcessing()
      this._showDiff(this.pendingOriginalText, request.corrected, request.provider, request.model)
      this.currentRequestId = null
      return
    }

    if (request.status === "failed") {
      this._hideProcessing()
      this.currentRequestId = null
      window.alert(request.error || "Falha ao processar com IA.")
      return
    }

    if (request.status === "canceled") {
      this._hideProcessing()
      this.currentRequestId = null
    }
  }

  _observeStreamSource() {
    const source = document.querySelector("turbo-cable-stream-source")
    if (!source) {
      this._setTransportState(false)
      return
    }

    this._setTransportState(source.hasAttribute("connected"))
    this.streamObserver = new MutationObserver(() => {
      this._setTransportState(source.hasAttribute("connected"))
    })
    this.streamObserver.observe(source, { attributes: true, attributeFilter: ["connected"] })
  }

  _setTransportState(connected) {
    this.realtimeConnected = connected
    if (!this.hasTransportBadgeTarget) return

    this.transportBadgeTarget.textContent = connected ? "Tempo real" : "Fallback polling"
    this.transportBadgeTarget.classList.toggle("nm-ai-transport--live", connected)
    this.transportBadgeTarget.classList.toggle("nm-ai-transport--fallback", !connected)
  }

  _upsertHistoryRequest(request) {
    const existingIndex = this.historyRequests.findIndex((item) => String(item.id) === String(request.id))

    if (existingIndex >= 0) {
      this.historyRequests.splice(existingIndex, 1, request)
    } else {
      this.historyRequests.unshift(request)
    }

    this.historyRequests = this.historyRequests
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 10)
  }

  _attemptLabel(attemptsCount, maxAttempts) {
    if (!attemptsCount || !maxAttempts) return ""
    return `Tentativa ${attemptsCount} de ${maxAttempts}`
  }

  _retryMessage(nextRetryAt, attemptsCount, maxAttempts) {
    const attemptLabel = this._attemptLabel(attemptsCount, maxAttempts)
    const countdown = this._secondsUntil(nextRetryAt)

    if (countdown == null) return attemptLabel || "Nova tentativa agendada"
    if (attemptLabel) return `${attemptLabel} • nova tentativa em ${countdown}s`
    return `Nova tentativa em ${countdown}s`
  }

  _pollDelayMs(data) {
    if (data.status !== "retrying") return 1000

    const seconds = this._secondsUntil(data.next_retry_at)
    if (seconds == null) return 1500

    return Math.min(Math.max(seconds * 1000, 1000), 10000)
  }

  _secondsUntil(isoTimestamp) {
    if (!isoTimestamp) return null

    const target = new Date(isoTimestamp).getTime()
    if (Number.isNaN(target)) return null

    return Math.max(0, Math.ceil((target - Date.now()) / 1000))
  }

  _renderDiff(diff, column) {
    return diff.map((item) => {
      const escaped = this._escapeHtml(item.value)

      if (item.type === "equal") return `<span class="ai-diff-equal">${escaped}</span>`
      if (item.type === "delete" && column === "original") return `<span class="ai-diff-del">${escaped}</span>`
      if (item.type === "insert" && column === "corrected") return `<span class="ai-diff-add">${escaped}</span>`
      return ""
    }).join("")
  }

  _renderHistory() {
    const requests = this._filteredHistoryRequests()
    this._syncHistoryFilters()

    if (!requests.length) {
      this.historyListTarget.innerHTML = ""
      this.historyEmptyTarget.classList.remove("hidden")
      this.historyStatusTarget.textContent = this._emptyHistoryLabel()
      return
    }

    this.historyEmptyTarget.classList.add("hidden")
    this.historyStatusTarget.textContent = this._historySummaryLabel(requests.length)
    this.historyListTarget.innerHTML = requests.map((request) => this._historyCard(request)).join("")
  }

  _filteredHistoryRequests() {
    switch (this.historyFilter) {
      case "active":
        return this.historyRequests.filter((request) => ["queued", "running", "retrying"].includes(request.status))
      case "failed":
        return this.historyRequests.filter((request) => request.status === "failed")
      case "succeeded":
        return this.historyRequests.filter((request) => request.status === "succeeded")
      default:
        return this.historyRequests
    }
  }

  _syncHistoryFilters() {
    this.historyFilterTargets.forEach((button) => {
      const selected = button.dataset.filterValue === this.historyFilter
      button.classList.toggle("is-active", selected)
    })
  }

  _historySummaryLabel(count) {
    const labels = {
      all: `${count} execucoes recentes`,
      active: `${count} execucoes ativas`,
      failed: `${count} falhas recentes`,
      succeeded: `${count} execucoes concluidas`
    }

    return labels[this.historyFilter] || labels.all
  }

  _emptyHistoryLabel() {
    const labels = {
      all: "Nenhuma execução recente.",
      active: "Nenhuma execução ativa.",
      failed: "Nenhuma falha recente.",
      succeeded: "Nenhuma execução concluída."
    }

    return labels[this.historyFilter] || labels.all
  }

  _historyCard(request) {
    const provider = request.provider && request.model ? `${request.provider}: ${request.model}` : (request.provider || "IA")
    const statusClass = this._statusClass(request.status)
    const duration = this._durationLabel(request)
    const error = request.error ? `<p class="mt-2 text-xs text-amber-300">${this._escapeHtml(request.error)}</p>` : ""
    const remoteHint = request.remote_hint
      ? `<p class="mt-2 text-xs ${request.remote_long_job ? "text-amber-300" : "text-[var(--theme-text-secondary)]"}">${this._escapeHtml(request.remote_hint)}</p>`
      : ""
    const preview = request.corrected
      ? `<p class="mt-2 text-xs text-[var(--theme-text-secondary)]">${this._escapeHtml(this._truncate(request.corrected, 120))}</p>`
      : ""

    return `
      <article class="rounded-lg border border-[var(--theme-border)] bg-[var(--theme-bg-secondary)] p-4">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-sm font-semibold text-[var(--theme-text-primary)]">${this._escapeHtml(this._capabilityLabel(request.capability))}</p>
            <p class="text-xs text-[var(--theme-text-muted)]">${this._escapeHtml(provider)}</p>
          </div>
          <span class="rounded-full px-2 py-1 text-[11px] font-medium ${statusClass}">
            ${this._escapeHtml(this._statusLabel(request.status))}
          </span>
        </div>
        <div class="mt-3 grid grid-cols-2 gap-2 text-xs text-[var(--theme-text-muted)]">
          <p>Tentativas: ${this._escapeHtml(String(request.attempts_count || 0))}/${this._escapeHtml(String(request.max_attempts || 0))}</p>
          <p>Duração: ${this._escapeHtml(duration)}</p>
          <p>Criado: ${this._escapeHtml(this._formatTimestamp(request.created_at))}</p>
          <p>Concluído: ${this._escapeHtml(this._formatTimestamp(request.completed_at))}</p>
        </div>
        ${remoteHint}
        ${preview}
        ${error}
      </article>
    `
  }

  _statusLabel(status) {
    return {
      queued: "Na fila",
      running: "Processando",
      retrying: "Repetindo",
      succeeded: "Concluida",
      failed: "Falhou",
      canceled: "Cancelada"
    }[status] || status
  }

  _capabilityLabel(capability) {
    return {
      grammar_review: "Revisao gramatical",
      suggest: "Sugestao",
      rewrite: "Reescrita",
      translate: "Traducao"
    }[capability] || capability
  }

  _statusClass(status) {
    return {
      queued: "bg-slate-800 text-slate-200",
      running: "bg-blue-950 text-blue-200",
      retrying: "bg-amber-950 text-amber-200",
      succeeded: "bg-emerald-950 text-emerald-200",
      failed: "bg-rose-950 text-rose-200",
      canceled: "bg-zinc-800 text-zinc-200"
    }[status] || "bg-zinc-800 text-zinc-200"
  }

  _formatTimestamp(value) {
    if (!value) return "—"

    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return value

    return date.toLocaleString("pt-BR", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    })
  }

  _renderSelectors() {
    if (!this.hasSelectorShellTarget) return

    this.selectorShellTarget.classList.toggle("hidden", !this.providerOptions.length)
    if (!this.hasProviderSelectTarget || !this.hasModelSelectTarget) return

    const currentProvider = this.selectedProvider() || this.aiProvider

    this.providerSelectTarget.innerHTML = this.providerOptions.map((option) => {
      const selected = option.name === currentProvider ? " selected" : ""
      return `<option value="${this._escapeHtml(option.name)}"${selected}>${this._escapeHtml(option.label || option.name)}</option>`
    }).join("")

    if (!this.providerSelectTarget.value && this.providerOptions[0]) {
      const fallback = this.providerOptions.find((option) => option.selected)?.name || this.providerOptions[0].name
      this.providerSelectTarget.value = fallback
    }

    this.providerSelectTarget.disabled = !this.aiEnabled
    this._renderModelOptions(this.providerSelectTarget.value)
  }

  _renderModelOptions(providerName) {
    const option = this.providerOptions.find((item) => item.name === providerName) || this.providerOptions[0]
    const models = option?.models || []
    const preferredModel = this.selectedModel() || option?.selected_model || option?.default_model || models[0] || ""

    this.modelSelectTarget.innerHTML = models.map((model) => {
      const selected = model === preferredModel ? " selected" : ""
      return `<option value="${this._escapeHtml(model)}"${selected}>${this._escapeHtml(model)}</option>`
    }).join("")

    if (!this.modelSelectTarget.value && preferredModel) {
      this.modelSelectTarget.value = preferredModel
    }

    this.modelSelectTarget.disabled = !this.aiEnabled || models.length <= 1
  }

  _truncate(text, limit) {
    if (!text || text.length <= limit) return text
    return `${text.slice(0, limit - 1)}…`
  }

  _durationLabel(request) {
    if (request.duration_human) return request.duration_human
    if (request.duration_ms) return `${request.duration_ms} ms`
    return "em andamento"
  }

  _joinMeta(...parts) {
    return parts.filter(Boolean).join(" • ")
  }

  _escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }

  _editor() {
    const editorPane = this.element.querySelector('[data-controller~="codemirror"]')
    const controller = editorPane && this.application.getControllerForElementAndIdentifier(editorPane, "codemirror")
    if (!controller) throw new Error("Editor indisponivel.")

    return controller
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  selectedProvider() {
    return this.hasProviderSelectTarget ? this.providerSelectTarget.value : this.aiProvider
  }

  selectedModel() {
    return this.hasModelSelectTarget ? this.modelSelectTarget.value : this.aiModel
  }

  selectedTargetLanguage() {
    return this.hasTargetLanguageSelectTarget ? this.targetLanguageSelectTarget.value : "en-US"
  }

  async _createTranslatedNote(content) {
    const requestId = this.lastCompletedRequest?.id
    if (!requestId) throw new Error("Request de tradução indisponível.")

    const response = await fetch(this._createTranslatedNoteUrl(requestId), {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this._csrfToken()
      },
      body: JSON.stringify({
        content,
        target_language: this.lastCompletedRequest?.targetLanguage || this.selectedTargetLanguage()
      })
    })
    const data = await response.json()
    if (!response.ok || data.error) throw new Error(data.error || "Falha ao criar nota traduzida.")

    this.dialogTarget.close()
    window.location.assign(data.note_url)
  }

  _createTranslatedNoteUrl(requestId) {
    return this.createTranslatedNoteUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }
}
