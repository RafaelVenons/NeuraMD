import { Controller } from "@hotwired/stimulus"
import { computeWordDiff } from "lib/diff_utils"

export default class extends Controller {
  static targets = [
    "workspace",
    "previewShell",
    "requestMenu",
    "requestMenuTitle",
    "requestMenuList",
    "configNotice",
    "processingBox",
    "processingState",
    "processingProvider",
    "processingHint",
    "processingMeta",
    "processingError",
    "queueDock",
    "resultBox",
    "proposalDiff",
    "correctedText",
    "historyDialog",
    "historyFilter",
    "historyList",
    "historyEmpty",
    "historyStatus",
    "acceptButton",
    "transportBadge",
    "translationMeta",
    "translationSummary",
    "translationTitle"
  ]

  static values = {
    statusUrl: String,
    reviewUrl: String,
    historyUrl: String,
    reorderUrl: String,
    requestUrlTemplate: String,
    retryUrlTemplate: String,
    cancelUrlTemplate: String,
    createTranslatedNoteUrlTemplate: String,
    noteTitle: String,
    noteLanguage: String,
    languageOptions: Array,
    languageLabels: Object
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
    this.dismissedQueueRequestIds = new Set()
    this.draggedQueueRequestId = null
    this.draggedQueueElement = null
    this.queuePlaceholder = null
    this.historyFilter = "all"
    this.realtimeConnected = false
    this.streamObserver = null
    this.pendingMenu = null
    this.activeTriggerButton = null
    this.activeTriggerHtml = null
    this.aiSuggestedText = ""
    this.preferredTargetLanguage = "en-US"
    this._boundDocumentClick = (event) => this._handleDocumentClick(event)
    this._handleRequestUpdate = (event) => this._handleStreamRequestUpdate(event)
    this._handlePromiseAiEnqueued = (event) => this._handlePromiseAiEnqueuedEvent(event)
    this.element.addEventListener("ai-request:update", this._handleRequestUpdate)
    this.element.addEventListener("promise:ai-enqueued", this._handlePromiseAiEnqueued)
    document.addEventListener("click", this._boundDocumentClick)
    this._observeStreamSource()
    this.checkAvailability()
    this.refreshHistory()
  }

  disconnect() {
    this.element.removeEventListener("ai-request:update", this._handleRequestUpdate)
    this.element.removeEventListener("promise:ai-enqueued", this._handlePromiseAiEnqueued)
    document.removeEventListener("click", this._boundDocumentClick)
    this.streamObserver?.disconnect()
    this._stopPolling()
    this._clearProposalStage()
    this._clearActiveTrigger()
  }

  openGrammar(event) {
    this.openMenu("grammar_review", event)
  }

  openSuggest(event) {
    this.openMenu("suggest", event)
  }

  openRewrite(event) {
    this.openMenu("rewrite", event)
  }

  openTranslate(event) {
    this.openMenu("translate", event)
  }

  async openMenu(capability, event) {
    event?.stopPropagation?.()
    this.lastOpenCapability = capability
    const trigger = event?.currentTarget || null

    try {
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

      this.pendingMenu = {
        capability,
        documentMarkdown,
        selectionRange: editor.getSelectionRange?.() || { from: 0, to: 0 },
        mode: capability === "translate" ? "translation_note" : (selection ? "selection" : "document"),
        targetLanguage,
        text,
        triggerButton: trigger
      }
      this._showRequestMenu(trigger, capability, this._buildExecutionOptions({ capability, text, targetLanguage }))
    } catch (error) {
      this._showProcessingFailure(error.message || "Falha ao abrir as opcoes de IA.")
    }
  }

  async runSelectedOption(event) {
    if (!this.pendingMenu) return

    await this._cancelCurrentRequest()
    this._setActiveTrigger(this.pendingMenu.triggerButton)
    this._hideRequestMenu()
    this._ensurePreviewVisible()

    this.pendingApplyMode = this.pendingMenu.mode
    this.pendingOriginalText = this.pendingMenu.mode === "translation_note"
      ? this.pendingMenu.text
      : this.pendingMenu.documentMarkdown
    this.lastCompletedRequest = null
    this.aiSuggestedText = ""
    this.pendingMenu.providerName = event.currentTarget.dataset.provider || this.aiProvider
    this.pendingMenu.modelName = event.currentTarget.dataset.strategy === "automatic"
      ? this._autoModelFor(
          this.pendingMenu.capability,
          this.pendingMenu.text,
          this.preferredTargetLanguage,
          this._providerModels(this.pendingMenu.providerName),
          this._providerDefaultModel(this.pendingMenu.providerName)
        )
      : event.currentTarget.dataset.model
    this.preferredTargetLanguage = event.currentTarget.dataset.targetLanguage || this.pendingMenu.targetLanguage || this.preferredTargetLanguage

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
          capability: this.pendingMenu.capability,
          provider: event.currentTarget.dataset.provider,
          model: event.currentTarget.dataset.strategy === "automatic" ? "" : event.currentTarget.dataset.model,
          target_language: this.preferredTargetLanguage,
          text: this.pendingMenu.text,
          document_markdown: this.pendingMenu.documentMarkdown
        })
      })

      const data = await response.json()
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao enfileirar processamento com IA.")

      this._startPolling(data.request_id)
      this.refreshHistory()
    } catch (error) {
      this._showProcessingFailure(error.message || "Falha ao processar com IA.")
      this._clearActiveTrigger()
    }
  }

  close() {
    this._cancelCurrentRequest()
    this._clearProposalStage()
    this._hideWorkspace()
  }

  async openHistory() {
    this.historyDialogTarget.showModal()
    this._syncHistoryFilters()
    await this.refreshHistory()
  }

  closeHistory() {
    this.historyDialogTarget.close()
  }

  async cancelProcessing() {
    await this._cancelCurrentRequest({ keepWorkspace: true })
    this._hideWorkspace()
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
      this._renderQueue()
    } catch (error) {
      this.historyRequests = []
      this.historyListTarget.innerHTML = ""
      this.historyEmptyTarget.classList.add("hidden")
      this.historyStatusTarget.textContent = error.message || "Falha ao carregar o histórico de IA."
      this._renderQueue()
    }
  }

  selectHistoryFilter(event) {
    this.historyFilter = event.currentTarget.dataset.filterValue || "all"
    this._syncHistoryFilters()
    this._renderHistory()
  }

  async queueAction(event) {
    const requestId = event.currentTarget.dataset.requestId
    const actionType = event.currentTarget.dataset.queueAction
    if (!requestId || !actionType) return

    if (actionType === "retry") {
      await this._retryRequest(requestId)
      return
    }

    if (actionType === "dismiss") {
      this.dismissedQueueRequestIds.add(String(requestId))
      this._renderQueue()
      return
    }

    await this._destroyRequest(requestId)
  }

  handleQueueDragStart(event) {
    const card = event.currentTarget
    const requestId = card.dataset.requestId
    if (!requestId || card.dataset.queueReorderable !== "true") {
      event.preventDefault()
      return
    }

    this.draggedQueueRequestId = requestId
    this.draggedQueueElement = card
    this.queuePlaceholder = this._buildQueuePlaceholder(card)

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", requestId)
    event.dataTransfer.setDragImage(this._transparentDragImage(), 0, 0)

    card.after(this.queuePlaceholder)
    requestAnimationFrame(() => card.classList.add("hidden"))
  }

  handleQueueDragOver(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    const targetCard = event.target.closest("[data-request-id][data-queue-reorderable='true']")
    if (!targetCard || targetCard === this.draggedQueueElement) return

    const rect = targetCard.getBoundingClientRect()
    const insertAfter = event.clientY > rect.top + (rect.height / 2)
    if (insertAfter) targetCard.after(this.queuePlaceholder)
    else targetCard.before(this.queuePlaceholder)
  }

  async handleQueueDrop(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    this.queuePlaceholder.before(this.draggedQueueElement)
    this.draggedQueueElement.classList.remove("hidden")
    this.queuePlaceholder.remove()

    const orderedRequestIds = Array.from(
      this.queueDockTarget.querySelectorAll("[data-request-id][data-queue-reorderable='true']")
    ).map((card) => card.dataset.requestId).reverse()

    this._cleanupQueueDrag()
    await this._persistQueueOrder(orderedRequestIds)
  }

  handleQueueDragEnd() {
    if (this.draggedQueueElement) this.draggedQueueElement.classList.remove("hidden")
    if (this.queuePlaceholder) this.queuePlaceholder.remove()
    this._cleanupQueueDrag()
  }

  async accept() {
    const editor = this._editor()
    const correctedText = this.hasCorrectedTextTarget ? this.correctedTextTarget.value : ""

    if (this.pendingApplyMode === "translation_note") {
      const previousLabel = this.acceptButtonTarget.textContent
      this.acceptButtonTarget.disabled = true
      this.acceptButtonTarget.textContent = "Criando nota..."

      try {
        await this._createTranslatedNote(correctedText)
      } catch (error) {
        window.alert(error.message || "Falha ao criar nota traduzida.")
      } finally {
        this.acceptButtonTarget.disabled = false
        this.acceptButtonTarget.textContent = previousLabel
      }
      return
    }

    this._clearProposalStage()
    editor.setValue(correctedText)

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
    this._hideWorkspace()
  }

  proposalChanged() {
    this._renderProposal()
  }

  proposalEditorChanged() {
    if (!this.hasProposalDiffTarget || !this.hasCorrectedTextTarget) return
    this.correctedTextTarget.value = this._proposalEditorText()
    this._renderProposal()
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
    } catch (_) {
      this.aiEnabled = false
      this.aiProvider = null
      this.aiModel = null
      this.providerOptions = []
    }
    this._syncPreferredTargetLanguage()
  }

  _showConfigNotice() {
    this._clearProposalStage()
    this._showWorkspace()
    this._clearActiveTrigger()
    this.configNoticeTarget.classList.remove("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
  }

  _showProcessing() {
    this._clearProposalStage()
    const provider = this.pendingMenu?.providerName || this.aiProvider
    const model = this.pendingMenu?.modelName || this.aiModel

    this._showWorkspace()
    this.configNoticeTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.remove("hidden")
    this.processingBoxTarget.classList.add("flex")
    this.processingProviderTarget.textContent = provider && model ? `${provider}: ${model}` : "IA"
    this.processingStateTarget.textContent = "Na fila"
    this.processingHintTarget.textContent = provider === "ollama"
      ? "Job remoto no AIrch. Pode continuar usando a aplicacao enquanto a tarefa roda."
      : "Processamento assíncrono em andamento."
    this.processingMetaTarget.textContent = "Aguardando execução..."
    this.processingErrorTarget.textContent = ""
    this.processingErrorTarget.classList.add("hidden")
  }

  _showProcessingFailure(message) {
    this._clearProposalStage()
    this._showWorkspace()
    this.configNoticeTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.remove("hidden")
    this.processingBoxTarget.classList.add("flex")
    this.processingStateTarget.textContent = "Falhou"
    this.processingHintTarget.textContent = "A requisição não pôde ser concluída."
    this.processingMetaTarget.textContent = ""
    this.processingErrorTarget.textContent = message
    this.processingErrorTarget.classList.remove("hidden")
  }

  _showProposal(corrected) {
    const editor = this._editor()
    const suggestionForPreview = this.pendingApplyMode === "translation_note"
      ? corrected
      : this._buildSuggestedDocument(corrected)

    this.aiSuggestedText = suggestionForPreview
    this.correctedTextTarget.value = suggestionForPreview

    this._showWorkspace()
    this.configNoticeTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.remove("hidden")
    this.resultBoxTarget.classList.add("flex")
    this.acceptButtonTarget.textContent =
      this.pendingApplyMode === "translation_note" ? "Criar nota traduzida" : "Aplicar"
    if (this.pendingApplyMode !== "translation_note") {
      editor.showAiDiff({
        originalText: editor.getValue(),
        aiSuggestedText: suggestionForPreview
      })
      this._setStageState(true)
    }
    this._renderProposal()
    this._syncTranslationMeta(suggestionForPreview)
  }

  _showWorkspace() {
    this.workspaceTarget.classList.remove("hidden")
    this.workspaceTarget.classList.add("flex")
    this.previewShellTarget.classList.add("hidden")
  }

  _hideWorkspace() {
    this.workspaceTarget.classList.add("hidden")
    this.workspaceTarget.classList.remove("flex")
    this.previewShellTarget.classList.remove("hidden")
    this.configNoticeTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.translationMetaTarget.classList.add("hidden")
    this._hideRequestMenu()
    this.pendingMenu = null
    this.aiSuggestedText = ""
    this._clearActiveTrigger()
  }

  _setStageState(active) {
    this.element.dispatchEvent(new CustomEvent("ai-review:stagechange", {
      detail: { active },
      bubbles: true
    }))
  }

  _buildSuggestedDocument(replacement) {
    const source = this.pendingMenu?.documentMarkdown || this._editor().getValue()
    if (this.pendingApplyMode !== "selection") return replacement

    const range = this.pendingMenu?.selectionRange || { from: 0, to: 0 }
    const from = Math.max(0, range?.from || 0)
    const to = Math.max(from, range?.to || from)
    return `${source.slice(0, from)}${replacement}${source.slice(to)}`
  }

  _clearProposalStage() {
    try {
      this._editor().clearAiDiff()
    } catch (_) {
    }
    this.aiSuggestedText = ""
    this._setStageState(false)
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
        this._showProposal(data.corrected)
        this._stopPolling()
        this.currentRequestId = null
        this._clearActiveTrigger()
        this.refreshHistory()
        return
      }

      if (data.status === "failed") throw new Error(data.error || "Falha ao processar com IA.")

      if (data.status === "canceled") {
        this._stopPolling()
        this.currentRequestId = null
        this._hideWorkspace()
        this.refreshHistory()
        return
      }

      if (this.pollAttempt >= 60) throw new Error("Tempo limite excedido aguardando a resposta da IA.")

      this.pollTimer = window.setTimeout(() => this._pollRequest(requestId), this._pollDelayMs(data))
    } catch (error) {
      this._stopPolling()
      this.currentRequestId = null
      this._showProcessingFailure(error.message || "Falha ao processar com IA.")
      this._clearActiveTrigger()
    }
  }

  _stopPolling() {
    if (this.pollTimer) {
      window.clearTimeout(this.pollTimer)
      this.pollTimer = null
    }
  }

  async _cancelCurrentRequest({ keepWorkspace = false } = {}) {
    const requestId = this.currentRequestId
    this._stopPolling()

    if (!requestId) {
      if (!keepWorkspace) this._clearActiveTrigger()
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
      this._clearActiveTrigger()
    }
  }

  _requestUrl(requestId) {
    return this.requestUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _cancelUrl(requestId) {
    return this.cancelUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _retryUrl(requestId) {
    return this.retryUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _updateProcessingState(data) {
    const attemptsCount = Number(data.attempts_count || 0)
    const maxAttempts = Number(data.max_attempts || 0)

    if (data.status === "retrying") {
      this.processingStateTarget.textContent = "Tentando novamente"
      this.processingHintTarget.textContent = data.remote_hint || "Nova tentativa agendada."
      this.processingMetaTarget.textContent = this._joinMeta(this._retryMessage(data.next_retry_at, attemptsCount, maxAttempts), this._durationLabel(data))
    } else if (data.status === "running") {
      this.processingStateTarget.textContent = "Processando"
      this.processingHintTarget.textContent = data.remote_hint || "Processamento assíncrono em andamento."
      this.processingMetaTarget.textContent = this._joinMeta(this._attemptLabel(attemptsCount, maxAttempts), this._durationLabel(data))
    } else if (data.status === "queued") {
      this.processingStateTarget.textContent = "Na fila"
      this.processingHintTarget.textContent = data.remote_hint || "Aguardando execução na fila."
      this.processingMetaTarget.textContent = this._joinMeta(this._attemptLabel(attemptsCount, maxAttempts) || "Aguardando execução...", this._durationLabel(data))
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
    if (this.historyDialogTarget?.open) this._renderHistory()
    this._renderQueue()
    if (String(request.id) !== String(this.currentRequestId)) return

    this._stopPolling()
    this._updateProcessingState(request)

    if (request.status === "succeeded") {
      this.lastCompletedRequest = {
        id: request.id,
        capability: request.capability,
        provider: request.provider,
        model: request.model,
        targetLanguage: request.target_language || this.selectedTargetLanguage()
      }
      this.currentRequestId = null
      this._showProposal(request.corrected)
      this._clearActiveTrigger()
      return
    }

    if (request.status === "failed") {
      this.currentRequestId = null
      this._showProcessingFailure(request.error || "Falha ao processar com IA.")
      this._clearActiveTrigger()
      return
    }

    if (request.status === "canceled") {
      this.currentRequestId = null
      this._hideWorkspace()
      this._clearActiveTrigger()
    }
  }

  async _handlePromiseAiEnqueuedEvent(event) {
    const requestId = event.detail?.requestId
    if (!requestId) return

    try {
      const response = await fetch(this._requestUrl(requestId), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const request = await response.json()
      if (!response.ok || !request?.id) return

      this._upsertHistoryRequest(request)
      if (this.historyDialogTarget?.open) this._renderHistory()
      this._renderQueue()
    } catch (_) {
    }
  }

  _observeStreamSource() {
    const source = document.querySelector("turbo-cable-stream-source")
    if (!source) {
      this._setTransportState(false)
      return
    }

    this._setTransportState(source.hasAttribute("connected"))
    this.streamObserver = new MutationObserver(() => this._setTransportState(source.hasAttribute("connected")))
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
    if (existingIndex >= 0) this.historyRequests.splice(existingIndex, 1, request)
    else this.historyRequests.unshift(request)

    this.historyRequests = this.historyRequests
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 10)

    this._renderQueue()
  }

  async _retryRequest(requestId) {
    try {
      const response = await fetch(this._retryUrl(requestId), {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        }
      })
      const data = await response.json()
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao reenfileirar request.")

      this.dismissedQueueRequestIds.delete(String(requestId))
      this._upsertHistoryRequest(data)
      if (this.historyDialogTarget?.open) this._renderHistory()
    } catch (error) {
      window.alert(error.message || "Falha ao reenfileirar request.")
    }
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

  _renderProposal() {
    const currentText = this.correctedTextTarget.value
    const selection = this._captureProposalSelection()
    const aiAnnotated = this._annotateAiSuggestion(this.pendingOriginalText, this.aiSuggestedText)
    const currentAnnotated = this._annotateCurrentSuggestion(aiAnnotated, this.aiSuggestedText, currentText)

    this.proposalDiffTarget.innerHTML = currentAnnotated.map((item) => {
      const escaped = this._escapeHtml(item.value)
      if (item.kind === "ai") return `<span class="rounded bg-emerald-400/15 px-0.5 text-emerald-200">${escaped}</span>`
      if (item.kind === "manual") return `<span class="rounded bg-amber-300/25 px-0.5 text-amber-200">${escaped}</span>`
      return `<span>${escaped}</span>`
    }).join("")
    this._restoreProposalSelection(selection)
  }

  _proposalEditorText() {
    return this.proposalDiffTarget.innerText.replace(/\u00a0/g, " ")
  }

  _annotateAiSuggestion(originalText, aiSuggestedText) {
    return computeWordDiff(originalText, aiSuggestedText).flatMap((item) => {
      if (item.type === "delete") return []
      if (item.type === "insert") return [{ value: item.value, kind: "ai" }]
      return [{ value: item.value, kind: "plain" }]
    })
  }

  _annotateCurrentSuggestion(aiAnnotated, aiSuggestedText, currentText) {
    const result = []
    const aiCursor = { index: 0, offset: 0 }

    computeWordDiff(aiSuggestedText, currentText).forEach((item) => {
      if (item.type === "delete") {
        this._consumeAnnotated(aiAnnotated, aiCursor, item.value.length)
        return
      }

      if (item.type === "insert") {
        result.push({ value: item.value, kind: "manual" })
        return
      }

      result.push(...this._consumeAnnotated(aiAnnotated, aiCursor, item.value.length))
    })

    return this._mergeAnnotated(result)
  }

  _consumeAnnotated(segments, cursor, length) {
    let remaining = length
    const consumed = []

    while (remaining > 0 && cursor.index < segments.length) {
      const segment = segments[cursor.index]
      const available = segment.value.length - cursor.offset
      const take = Math.min(remaining, available)
      const value = segment.value.slice(cursor.offset, cursor.offset + take)

      if (value) consumed.push({ value, kind: segment.kind })

      cursor.offset += take
      remaining -= take

      if (cursor.offset >= segment.value.length) {
        cursor.index += 1
        cursor.offset = 0
      }
    }

    return consumed
  }

  _mergeAnnotated(segments) {
    return segments.reduce((merged, segment) => {
      if (!segment.value) return merged
      const previous = merged[merged.length - 1]
      if (previous && previous.kind === segment.kind) previous.value += segment.value
      else merged.push({ ...segment })
      return merged
    }, [])
  }

  _captureProposalSelection() {
    if (!this.hasProposalDiffTarget) return null
    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0) return null
    if (!this.proposalDiffTarget.contains(selection.anchorNode)) return null

    return {
      anchor: this._textOffsetForNode(selection.anchorNode, selection.anchorOffset),
      focus: this._textOffsetForNode(selection.focusNode, selection.focusOffset)
    }
  }

  _restoreProposalSelection(selectionState) {
    if (!selectionState || !this.hasProposalDiffTarget) return
    const selection = window.getSelection()
    if (!selection) return

    const range = document.createRange()
    const anchor = this._nodeForTextOffset(selectionState.anchor)
    const focus = this._nodeForTextOffset(selectionState.focus)
    if (!anchor || !focus) return

    range.setStart(anchor.node, anchor.offset)
    range.collapse(true)
    selection.removeAllRanges()
    selection.addRange(range)
    selection.extend(focus.node, focus.offset)
  }

  _textOffsetForNode(targetNode, targetOffset) {
    let offset = 0
    const walker = document.createTreeWalker(this.proposalDiffTarget, NodeFilter.SHOW_TEXT)
    let node = walker.nextNode()

    while (node) {
      if (node === targetNode) return offset + Math.min(targetOffset, node.textContent.length)
      offset += node.textContent.length
      node = walker.nextNode()
    }

    return offset
  }

  _nodeForTextOffset(targetOffset) {
    let offset = 0
    const walker = document.createTreeWalker(this.proposalDiffTarget, NodeFilter.SHOW_TEXT)
    let node = walker.nextNode()

    while (node) {
      const length = node.textContent.length
      if (targetOffset <= offset + length) {
        return { node, offset: Math.max(0, targetOffset - offset) }
      }
      offset += length
      node = walker.nextNode()
    }

    if (this.proposalDiffTarget.lastChild?.nodeType === Node.TEXT_NODE) {
      const node = this.proposalDiffTarget.lastChild
      return { node, offset: node.textContent.length }
    }

    const fallback = document.createTextNode("")
    this.proposalDiffTarget.appendChild(fallback)
    return { node: fallback, offset: 0 }
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
      case "active": return this.historyRequests.filter((request) => ["queued", "running", "retrying"].includes(request.status))
      case "failed": return this.historyRequests.filter((request) => request.status === "failed")
      case "succeeded": return this.historyRequests.filter((request) => request.status === "succeeded")
      default: return this.historyRequests
    }
  }

  _syncHistoryFilters() {
    this.historyFilterTargets.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.filterValue === this.historyFilter)
    })
  }

  _historySummaryLabel(count) {
    return {
      all: `${count} execucoes recentes`,
      active: `${count} execucoes ativas`,
      failed: `${count} falhas recentes`,
      succeeded: `${count} execucoes concluidas`
    }[this.historyFilter] || `${count} execucoes recentes`
  }

  _emptyHistoryLabel() {
    return {
      all: "Nenhuma execução recente.",
      active: "Nenhuma execução ativa.",
      failed: "Nenhuma falha recente.",
      succeeded: "Nenhuma execução concluída."
    }[this.historyFilter] || "Nenhuma execução recente."
  }

  _historyCard(request) {
    const provider = request.provider && request.model ? `${request.provider}: ${request.model}` : (request.provider || "IA")
    const statusClass = this._statusClass(request.status)
    const duration = this._durationLabel(request)
    const error = request.error ? `<p class="mt-2 text-xs text-amber-300">${this._escapeHtml(request.error)}</p>` : ""
    const remoteHint = request.remote_hint ? `<p class="mt-2 text-xs ${request.remote_long_job ? "text-amber-300" : "text-[var(--theme-text-secondary)]"}">${this._escapeHtml(request.remote_hint)}</p>` : ""

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
        ${error}
      </article>
    `
  }

  _renderQueue() {
    if (!this.hasQueueDockTarget) return

    const requests = this._sortedQueueRequests()
      .filter((request) => !this.dismissedQueueRequestIds.has(String(request.id)))
      .slice(0, 6)

    if (requests.length === 0) {
      this.queueDockTarget.innerHTML = ""
      this.queueDockTarget.classList.add("hidden")
      return
    }

    this.queueDockTarget.classList.remove("hidden")
    this.queueDockTarget.innerHTML = requests.map((request) => this._queueCard(request)).join("")
  }

  _queueEligible(request) {
    if (["queued", "running", "retrying", "failed"].includes(request.status)) return true
    return request.capability === "seed_note" && request.status === "succeeded"
  }

  _sortedQueueRequests() {
    const supplemental = this.historyRequests
      .filter((request) => this._queueEligible(request))
      .filter((request) => !this._queueReorderable(request))
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))

    const active = this.historyRequests
      .filter((request) => this._queueEligible(request))
      .filter((request) => this._queueReorderable(request))
      .sort((left, right) => {
        const leftPos = Number(left.queue_position || 0)
        const rightPos = Number(right.queue_position || 0)
        if (leftPos !== rightPos) return rightPos - leftPos
        return new Date(right.created_at || 0) - new Date(left.created_at || 0)
      })

    return [...supplemental, ...active]
  }

  _queueCard(request) {
    const noteTitle = request.promise_note_title || request.note_title || "Nota"
    const serviceLabel = this._queueServiceLabel(request)
    const modelLabel = request.model || request.provider || "IA"
    const borderClass = this._queueBorderClass(request.status)
    const reorderable = this._queueReorderable(request)
    const cardAction = request.status === "failed" ? "retry" : ""
    const cardActionAttr = cardAction ? `data-request-id="${this._escapeHtml(request.id)}" data-queue-action="${cardAction}" data-action="click->ai-review#queueAction"` : ""
    const cardInteractiveClass = cardAction ? "cursor-pointer hover:bg-[var(--theme-bg-hover)]" : ""
    const dragAttrs = reorderable
      ? `draggable="true"
         data-request-id="${this._escapeHtml(request.id)}"
         data-queue-reorderable="true"
         data-action="dragstart->ai-review#handleQueueDragStart dragend->ai-review#handleQueueDragEnd dragover->ai-review#handleQueueDragOver drop->ai-review#handleQueueDrop"`
      : `data-request-id="${this._escapeHtml(request.id)}" data-queue-reorderable="false"`
    const titleClass = request.status === "failed" ? "text-red-300" : "text-[var(--theme-text-primary)]"
    const dragClass = reorderable ? "cursor-grab active:cursor-grabbing" : ""

    return `
      <article class="pointer-events-auto w-56 max-w-[calc(100vw-1.5rem)] rounded-xl border-2 ${borderClass} bg-[var(--theme-bg-secondary)] px-2.5 py-2 shadow-xl backdrop-blur transition ${cardInteractiveClass} ${dragClass}" ${dragAttrs} ${cardActionAttr}>
        <div class="flex items-start gap-3">
          <div class="min-w-0 flex-1">
            <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-[var(--theme-text-faint)]">${this._escapeHtml(serviceLabel)}</p>
            <p class="mt-1 truncate text-sm font-semibold ${titleClass}">${this._escapeHtml(noteTitle)}</p>
            <p class="mt-1 truncate text-[11px] text-[var(--theme-text-secondary)]">${this._escapeHtml(modelLabel)}</p>
          </div>
          <div class="flex flex-col items-end gap-2">
            ${this._queueActionButton(request)}
          </div>
        </div>
      </article>
    `
  }

  _queueActionButton(request) {
    if (["queued", "running", "retrying"].includes(request.status) || (request.capability === "seed_note" && request.status === "succeeded")) {
      const label = request.capability === "seed_note" && request.status === "succeeded" ? "↺" : "X"
      const action = request.capability === "seed_note" && request.status === "succeeded" ? "undo" : "cancel"
      const title = request.capability === "seed_note" && request.status === "succeeded" ? "Desfazer" : "Cancelar"

      return `
        <button type="button"
                title="${title}"
                aria-label="${title}"
                class="rounded-full border border-red-700 bg-red-900/40 px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:text-red-400"
                data-request-id="${this._escapeHtml(request.id)}"
                data-queue-action="${action}"
                data-action="click->ai-review#queueAction">
          ${label}
        </button>
      `
    }

    if (request.status === "failed") {
      return `
        <span class="rounded-full border border-red-700 bg-red-900/40 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-red-300">
          Retry
        </span>
      `
    }

    return `
      <button type="button"
              title="Fechar"
              aria-label="Fechar"
              class="rounded-full border border-[var(--theme-border)] px-2 py-0.5 text-[11px] text-[var(--theme-text-faint)] hover:bg-[var(--theme-bg-hover)]"
              data-request-id="${this._escapeHtml(request.id)}"
              data-queue-action="dismiss"
              data-action="click->ai-review#queueAction">
        ×
      </button>
    `
  }

  _queueReorderable(request) {
    return ["queued", "running", "retrying"].includes(request.status)
  }

  _queueServiceLabel(request) {
    const labels = {
      grammar_review: {
        queued: "Revisar",
        running: "Revisando",
        retrying: "Revisando",
        succeeded: "Revisado",
        failed: "Revisar"
      },
      rewrite: {
        queued: "Markdown",
        running: "Markdown...",
        retrying: "Markdown...",
        succeeded: "Markdown",
        failed: "Markdown"
      },
      suggest: {
        queued: "Sugestao",
        running: "Sugerindo",
        retrying: "Sugerindo",
        succeeded: "Sugerido",
        failed: "Sugestao"
      },
      translate: {
        queued: "Traduzir",
        running: "Traduzindo",
        retrying: "Traduzindo",
        succeeded: "Traduzido",
        failed: "Traduzir"
      },
      seed_note: {
        queued: "Criar",
        running: "Criando",
        retrying: "Criando",
        succeeded: "Criado",
        failed: "Criar"
      }
    }

    return labels[request.capability]?.[request.status] || this._statusLabel(request.status)
  }

  _queueBorderClass(status) {
    return {
      queued: "border-gray-700",
      running: "border-yellow-400",
      retrying: "border-yellow-400",
      succeeded: "border-green-400",
      failed: "border-red-700",
      canceled: "border-zinc-700"
    }[status] || "border-[var(--theme-border)]"
  }

  _buildQueuePlaceholder(card) {
    const placeholder = document.createElement("div")
    placeholder.className = "pointer-events-none w-56 max-w-[calc(100vw-1.5rem)] rounded-xl border-2 border-dashed border-[var(--theme-border)] bg-transparent px-2.5 py-5 opacity-70"
    placeholder.dataset.queuePlaceholder = "true"
    return placeholder
  }

  _transparentDragImage() {
    if (this._dragImage) return this._dragImage

    const canvas = document.createElement("canvas")
    canvas.width = 1
    canvas.height = 1
    this._dragImage = canvas
    return canvas
  }

  _cleanupQueueDrag() {
    this.draggedQueueRequestId = null
    this.draggedQueueElement = null
    this.queuePlaceholder = null
  }

  async _persistQueueOrder(orderedRequestIds) {
    if (!orderedRequestIds.length) return

    try {
      const response = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify({ ordered_request_ids: orderedRequestIds })
      })
      const data = await response.json()
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao reordenar fila.")

      ;(data.requests || []).forEach((request) => this._upsertHistoryRequest(request))
      if (this.historyDialogTarget?.open) this._renderHistory()
      this._renderQueue()
    } catch (error) {
      window.alert(error.message || "Falha ao reordenar fila.")
      this.refreshHistory()
    }
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

  _syncTranslationMeta(correctedText) {
    const active = this.pendingApplyMode === "translation_note"
    this.translationMetaTarget.classList.toggle("hidden", !active)
    if (!active) return

    const targetLanguage = this.lastCompletedRequest?.targetLanguage || this.selectedTargetLanguage()
    this.translationSummaryTarget.textContent = `Uma nova nota irma sera criada em ${this._languageLabel(targetLanguage)} e vinculada a esta nota.`
    this.translationTitleTarget.value = this._defaultTranslatedTitle(correctedText, targetLanguage)
  }

  _defaultTranslatedTitle(content, targetLanguage) {
    const headingMatch = String(content || "").match(/^\s*#\s+(.+)$/m)
    if (headingMatch?.[1]) return headingMatch[1].trim()

    const baseTitle = this.noteTitleValue || "Nota traduzida"
    return `${baseTitle} (${this._languageLabel(targetLanguage)})`
  }

  _languageLabel(languageCode) {
    if (!languageCode) return "Idioma"
    const labels = {
      "pt-BR": "Portugues",
      "en-US": "English",
      es: "Espanol",
      de: "Deutsch",
      fr: "Francais",
      it: "Italiano",
      "zh-CN": "Chinese (Simplified)",
      "zh-TW": "Chinese (Traditional)",
      "ja-JP": "Japanese",
      "ko-KR": "Korean"
    }
    return this.languageLabelsValue?.[languageCode] || labels[languageCode] || languageCode
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

  _editorController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "editor")
  }

  _ensurePreviewVisible() {
    this._editorController()?.showPreview?.()
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  selectedTargetLanguage() {
    return this.preferredTargetLanguage || this.languageOptionsValue?.[0] || "en-US"
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
        title: this.hasTranslationTitleTarget ? this.translationTitleTarget.value : "",
        target_language: this.lastCompletedRequest?.targetLanguage || this.selectedTargetLanguage()
      })
    })
    const data = await response.json()
    if (!response.ok || data.error) throw new Error(data.error || "Falha ao criar nota traduzida.")
    window.location.assign(data.note_url)
  }

  _createTranslatedNoteUrl(requestId) {
    return this.createTranslatedNoteUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  async _destroyRequest(requestId) {
    const response = await fetch(this._cancelUrl(requestId), {
      method: "DELETE",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this._csrfToken()
      }
    })
    const data = await response.json()
    if (!response.ok || data.error) throw new Error(data.error || "Falha ao cancelar request de IA.")

    const request = this.historyRequests.find((item) => String(item.id) === String(requestId))
    if (request) {
      request.status = data.status
      this._upsertHistoryRequest(request)
    }

    if (data.undone) {
      this.dismissedQueueRequestIds.add(String(requestId))
      this._restorePromiseLinkInEditor(data.promise_note_id, data.restored_content)
    } else if (data.status === "canceled") {
      this.dismissedQueueRequestIds.add(String(requestId))
    }

    if (data.graph_changed) {
      document.dispatchEvent(new CustomEvent("autosave:saved", {
        detail: { kind: "draft", graphChanged: true }
      }))
    }

    if (this.historyDialogTarget?.open) this._renderHistory()
    this._renderQueue()
  }

  _restorePromiseLinkInEditor(noteId, restoredContent) {
    const editor = this._editor()
    if (restoredContent) {
      editor.setValue(restoredContent)
      return
    }

    const current = editor.getValue()
    const escapedNoteId = String(noteId || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    if (!escapedNoteId) return

    const reverted = current.replace(new RegExp(`\\[\\[([^\\]|]+)\\|(?:[a-z]+:)?${escapedNoteId}\\]\\]`, "gi"), "[[$1]]")
    if (reverted !== current) editor.setValue(reverted)
  }

  _showRequestMenu(trigger, capability, suggestions) {
    if (!trigger || !this.hasRequestMenuTarget) return

    const rect = trigger.getBoundingClientRect()
    this.requestMenuTarget.style.top = `${rect.bottom + window.scrollY + 8}px`
    this.requestMenuTarget.style.left = `${Math.max(12, rect.left + window.scrollX - 12)}px`
    this.requestMenuTitleTarget.textContent = capability === "translate" ? "Escolha idioma e modelo" : "Escolha como processar"
    this.requestMenuListTarget.innerHTML = suggestions.map((option) => {
      const description = option.description ? `<p class="mt-0.5 text-xs text-[var(--theme-text-muted)]">${this._escapeHtml(option.description)}</p>` : ""
      return `
        <button type="button"
                class="block w-full rounded-lg px-3 py-2 text-left hover:bg-[var(--theme-bg-tertiary)]"
                data-action="click->ai-review#runSelectedOption"
                data-provider="${this._escapeHtml(option.provider || "")}"
                data-model="${this._escapeHtml(option.model || "")}"
                data-strategy="${this._escapeHtml(option.strategy)}"
                data-target-language="${this._escapeHtml(option.targetLanguage || "")}">
          <span class="block text-sm text-[var(--theme-text-primary)]">${this._escapeHtml(option.label)}</span>
          ${description}
        </button>
      `
    }).join("")
    this.requestMenuTarget.classList.remove("hidden")
  }

  _hideRequestMenu() {
    if (!this.hasRequestMenuTarget) return
    this.requestMenuTarget.classList.add("hidden")
  }

  _buildExecutionOptions({ capability, text, targetLanguage }) {
    const providers = this.providerOptions.length ? this.providerOptions : [{
      name: this.aiProvider,
      label: this.aiProvider || "IA",
      default_model: this.aiModel,
      models: this.aiModel ? [this.aiModel] : []
    }]

    if (capability === "translate") {
      const languages = this.languageOptionsValue?.length ? this.languageOptionsValue : [targetLanguage || this.selectedTargetLanguage()]
      return languages.flatMap((languageCode) => {
        return providers.flatMap((option) => this._providerExecutionOptions({
          capability,
          provider: option,
          text,
          targetLanguage: languageCode,
          labelPrefix: this._languageLabel(languageCode)
        }))
      })
    }

    return providers.flatMap((option) => this._providerExecutionOptions({
      capability,
      provider: option,
      text,
      targetLanguage
    }))
  }

  _providerExecutionOptions({ capability, provider, text, targetLanguage, labelPrefix = null }) {
    const models = provider?.models?.length ? provider.models : [provider?.default_model].filter(Boolean)
    const autoModel = this._autoModelFor(capability, text, targetLanguage, models, provider?.default_model)
    const optionPrefix = labelPrefix ? `${labelPrefix} · ` : ""
    const providerLabel = provider?.label || provider?.name || "IA"
    const options = [{
      label: `${optionPrefix}Automatico · ${providerLabel}`,
      provider: provider?.name || this.aiProvider,
      model: "",
      strategy: "automatic",
      targetLanguage,
      description: this._autoDescription(capability, autoModel || provider?.default_model, text, providerLabel, targetLanguage)
    }]

    models.forEach((model) => {
      options.push({
        label: `${optionPrefix}${providerLabel} · ${model}`,
        provider: provider?.name || this.aiProvider,
        model,
        strategy: "manual_override",
        targetLanguage,
        description: this._modelHint(model, capability, targetLanguage)
      })
    })

    return options
  }

  _providerModels(providerName) {
    const provider = this.providerOptions.find((item) => item.name === providerName)
    return provider?.models?.length ? provider.models : [provider?.default_model].filter(Boolean)
  }

  _providerDefaultModel(providerName) {
    return this.providerOptions.find((item) => item.name === providerName)?.default_model || this.aiModel
  }

  _autoModelFor(capability, text, targetLanguage, availableModels = [], fallbackModel = null) {
    const length = text.toString().length
    const preferred = (() => {
      switch (capability) {
        case "grammar_review": return length <= 800 ? "qwen2.5:0.5b" : "qwen2.5:1.5b"
        case "suggest": return length <= 900 ? "qwen2:1.5b" : "qwen2.5:3b"
        case "rewrite": return length <= 900 ? "qwen2.5:1.5b" : "llama3.2:3b"
        case "translate": return targetLanguage === "en-US" ? (length <= 1200 ? "qwen2:1.5b" : "qwen2.5:3b") : "qwen2.5:3b"
        default: return fallbackModel || this.aiModel
      }
    })()

    if (availableModels.includes(preferred)) return preferred
    if (fallbackModel && availableModels.includes(fallbackModel)) return fallbackModel
    return availableModels[0] || fallbackModel || this.aiModel
  }

  _autoDescription(capability, model, text, providerLabel, targetLanguage) {
    const size = text.length <= 900 ? "trecho curto" : "texto maior"
    const translationHint = capability === "translate" ? ` para ${this._languageLabel(targetLanguage)}` : ""
    return `${this._capabilityLabel(capability)}${translationHint} via ${providerLabel}, com roteamento por ${size} e sugestao ${model || "padrao"}.`
  }

  _modelHint(model, capability, targetLanguage) {
    const hints = {
      "qwen2.5:0.5b": "Mais leve e rapido para revisoes curtas.",
      "qwen2.5:1.5b": "Equilibrio geral para revisao e reescrita.",
      "qwen2.5:3b": "Mais qualidade para textos maiores.",
      "qwen2:1.5b": capability === "translate" ? "Bom custo/qualidade para traducao pt-en." : "Resposta rapida com boa qualidade geral.",
      "llama3.2:1b": "Alternativa leve para respostas curtas.",
      "llama3.2:3b": "Melhor fluidez, com mais latencia."
    }
    const suffix = capability === "translate" && targetLanguage ? ` Idioma alvo: ${this._languageLabel(targetLanguage)}.` : ""
    return `${hints[model] || "Execucao manual neste modelo."}${suffix}`
  }

  _syncPreferredTargetLanguage() {
    const languages = this.languageOptionsValue || []
    if (languages.includes(this.preferredTargetLanguage)) return
    this.preferredTargetLanguage = languages.includes("en-US") ? "en-US" : (languages[0] || "en-US")
  }

  _handleDocumentClick(event) {
    if (!this.hasRequestMenuTarget || this.requestMenuTarget.classList.contains("hidden")) return
    if (this.requestMenuTarget.contains(event.target)) return
    if (event.target.closest("[data-action*='ai-review#open']")) return
    this._hideRequestMenu()
  }

  _setActiveTrigger(button) {
    if (!button) return
    this._clearActiveTrigger()
    this.activeTriggerButton = button
    this.activeTriggerHtml = button.innerHTML
    button.disabled = true
    button.classList.add("toolbar-btn--active")
    button.innerHTML = `
      <svg class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"></circle>
        <path class="opacity-90" fill="currentColor" d="M12 2a10 10 0 0 1 10 10h-3a7 7 0 0 0-7-7z"></path>
      </svg>
    `
  }

  _clearActiveTrigger() {
    if (!this.activeTriggerButton) return
    this.activeTriggerButton.disabled = false
    this.activeTriggerButton.classList.remove("toolbar-btn--active")
    this.activeTriggerButton.innerHTML = this.activeTriggerHtml
    this.activeTriggerButton = null
    this.activeTriggerHtml = null
  }
}
