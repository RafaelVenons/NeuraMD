import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import { computeWordDiff } from "lib/diff_utils"
import { emojiExtension, superscriptExtension, subscriptExtension, highlightExtension, wikilinkExtension } from "lib/marked_extensions"

const PENDING_SEED_NOTE_REVIEW_STORAGE_KEY = "nm:pending-seed-note-review"
const PENDING_COMPLETED_REQUEST_REVIEW_STORAGE_KEY = "nm:pending-completed-request-review"

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
    "proposalPanels",
    "proposalRawPane",
    "proposalPreviewPane",
    "historyDialog",
    "historyButton",
    "historyFilter",
    "historyList",
    "historyEmpty",
    "historyStatus",
    "acceptButton",
    "declineButton",
    "translationMeta",
    "translationSummary",
    "translationTitle"
  ]

  static values = {
    queueUrl: String,
    queueReorderUrl: String,
    queueRequestUrlTemplate: String,
    queueRetryUrlTemplate: String,
    queueCancelUrlTemplate: String,
    queueResolveUrlTemplate: String,
    statusUrl: String,
    reviewUrl: String,
    historyUrl: String,
    reorderUrl: String,
    requestUrlTemplate: String,
    retryUrlTemplate: String,
    cancelUrlTemplate: String,
    resolveUrlTemplate: String,
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
    this.queuePollTimer = null
    this.queuePollIntervalMs = null
    this.pollAttempt = 0
    this.pendingApplyMode = "document"
    this.pendingOriginalText = ""
    this.historyRequests = []
    this.globalHistoryRequests = []
    this.queueRequests = []
    this.promiseQueueWatchers = new Map()
    this.dismissedQueueRequestIds = new Set()
    this.canceledQueueRequestIds = new Set()
    this.resolvedQueueRequestIds = new Set()
    this.draggedQueueRequestId = null
    this.draggedQueueElement = null
    this.queuePlaceholder = null
    this.queueRenderDeferred = false
    this.pendingQueuePointerDrag = null
    this.queuePointerDragActive = false
    this.queueDockSuppressed = false
    this.seedNotePreviewMode = false
    this.historyFilter = "all"
    this.realtimeConnected = false
    this.streamObserver = null
    this.pendingMenu = null
    this.activeTriggerButton = null
    this.activeTriggerHtml = null
    this.aiSuggestedText = ""
    this.preferredTargetLanguage = "en-US"
    this._boundDocumentClick = (event) => this._handleDocumentClick(event)
    this._boundQueuePointerMove = (event) => this.handleQueuePointerMove(event)
    this._boundQueuePointerUp = (event) => this.handleQueuePointerUp(event)
    this._handleRequestUpdate = (event) => this._handleStreamRequestUpdate(event)
    this._handlePromiseAiEnqueued = (event) => this._handlePromiseAiEnqueuedEvent(event)
    this.element.addEventListener("ai-request:update", this._handleRequestUpdate)
    this.element.addEventListener("promise:ai-enqueued", this._handlePromiseAiEnqueued)
    document.addEventListener("click", this._boundDocumentClick)
    window.addEventListener("pointermove", this._boundQueuePointerMove)
    window.addEventListener("pointerup", this._boundQueuePointerUp)
    marked.use({ extensions: [wikilinkExtension, emojiExtension, superscriptExtension, subscriptExtension, highlightExtension] })
    marked.setOptions({ gfm: true, breaks: false })
    this._observeStreamSource()
    this._restorePendingSeedNoteReview()
    this._restorePendingCompletedRequestReview()
    this.checkAvailability()
    this.refreshQueue()
    this.refreshHistory()
  }

  disconnect() {
    this.element.removeEventListener("ai-request:update", this._handleRequestUpdate)
    this.element.removeEventListener("promise:ai-enqueued", this._handlePromiseAiEnqueued)
    document.removeEventListener("click", this._boundDocumentClick)
    window.removeEventListener("pointermove", this._boundQueuePointerMove)
    window.removeEventListener("pointerup", this._boundQueuePointerUp)
    this.streamObserver?.disconnect()
    this._stopPolling()
    this._stopQueuePolling()
    this._stopAllPromiseQueueWatchers()
    this._clearProposalStage()
    this._clearActiveTrigger()
  }

  hydrateNoteContext(payload) {
    const urls = payload.urls || {}
    const ai = payload.ai || {}

    this.queueUrlValue = urls.queue || this.queueUrlValue
    this.queueReorderUrlValue = urls.queue_reorder || this.queueReorderUrlValue
    this.queueRequestUrlTemplateValue = urls.queue_request_template || this.queueRequestUrlTemplateValue
    this.queueRetryUrlTemplateValue = urls.queue_retry_template || this.queueRetryUrlTemplateValue
    this.queueCancelUrlTemplateValue = urls.queue_cancel_template || this.queueCancelUrlTemplateValue
    this.queueResolveUrlTemplateValue = urls.queue_resolve_template || this.queueResolveUrlTemplateValue
    this.statusUrlValue = urls.ai_status || this.statusUrlValue
    this.reviewUrlValue = urls.ai_review || this.reviewUrlValue
    this.historyUrlValue = urls.ai_history || this.historyUrlValue
    this.reorderUrlValue = urls.ai_reorder || this.reorderUrlValue
    this.requestUrlTemplateValue = urls.ai_request_template || this.requestUrlTemplateValue
    this.retryUrlTemplateValue = urls.ai_retry_template || this.retryUrlTemplateValue
    this.cancelUrlTemplateValue = urls.ai_cancel_template || this.cancelUrlTemplateValue
    this.resolveUrlTemplateValue = urls.ai_resolve_template || this.resolveUrlTemplateValue
    this.createTranslatedNoteUrlTemplateValue =
      urls.ai_create_translated_note_template || this.createTranslatedNoteUrlTemplateValue
    this.noteTitleValue = ai.note_title || this.noteTitleValue
    this.noteLanguageValue = ai.note_language || this.noteLanguageValue
    this.languageOptionsValue = ai.language_options || this.languageOptionsValue
    this.languageLabelsValue = ai.language_labels || this.languageLabelsValue

    this._restorePendingSeedNoteReview(urls.show || window.location.pathname)
    this._restorePendingCompletedRequestReview(urls.show || window.location.pathname)
    if (this.historyDialogTarget?.open) this.refreshHistory()
    this._syncQueuePolling()
  }

  openGrammar(event) {
    this.openMenu("grammar_review", event)
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

    await this._runPendingRequest({
      providerName: event.currentTarget.dataset.provider || this.aiProvider,
      modelName: event.currentTarget.dataset.model,
      strategy: event.currentTarget.dataset.strategy,
      targetLanguage: event.currentTarget.dataset.targetLanguage || this.pendingMenu.targetLanguage || this.preferredTargetLanguage
    })
  }

  async runTranslateOption(event) {
    event.preventDefault()
    if (!this.pendingMenu) return

    const form = event.currentTarget.closest("form")
    if (!form) return

    const languageSelect = form.querySelector("[data-ai-review-translate-language]")
    const modelSelect = form.querySelector("[data-ai-review-translate-model]")
    const selectedModelOption = modelSelect?.selectedOptions?.[0]

    await this._runPendingRequest({
      providerName: selectedModelOption?.dataset.provider || this.aiProvider,
      modelName: selectedModelOption?.dataset.model || "",
      strategy: selectedModelOption?.dataset.strategy || "automatic",
      targetLanguage: languageSelect?.value || this.preferredTargetLanguage
    })
  }

  async _runPendingRequest({ providerName, modelName, strategy, targetLanguage }) {
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
    this.pendingMenu.providerName = providerName || this.aiProvider
    this.pendingMenu.modelName = strategy === "automatic"
      ? this._autoModelFor(
          this.pendingMenu.capability,
          this.pendingMenu.text,
          targetLanguage,
          this._providerModels(this.pendingMenu.providerName),
          this._providerDefaultModel(this.pendingMenu.providerName)
        )
      : modelName
    this.preferredTargetLanguage = targetLanguage

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
          provider: this.pendingMenu.providerName,
          model: strategy === "automatic" ? "" : modelName,
          target_language: this.preferredTargetLanguage,
          text: this.pendingMenu.text,
          document_markdown: this.pendingMenu.documentMarkdown
        })
      })

      const data = await this._parseJsonResponse(response, "Falha ao enfileirar processamento com IA.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao enfileirar processamento com IA.")

      this._startPolling(data.request_id)
      this.refreshHistory()
      this.refreshQueue()
    } catch (error) {
      this._showProcessingFailure(error.message || "Falha ao processar com IA.")
      this._clearActiveTrigger()
    }
  }

  async close() {
    this._cancelCurrentRequest()
    await this._rejectPendingResult()
    this._clearProposalStage()
    this._hideWorkspace()
  }

  async openHistory(event) {
    event?.preventDefault()
    event?.stopPropagation()
    if (this.historyDialogTarget.open) {
      this.closeHistory()
      return
    }

    this._positionHistoryDialog(event?.currentTarget || this.historyButtonTarget)
    this.historyDialogTarget.show()
    this.historyFilter = "all"
    this._syncHistoryFilters()
    await this.refreshQueue()
    this._renderHistory()
  }

  closeHistory() {
    if (this.historyDialogTarget.open) this.historyDialogTarget.close()
  }

  async cancelProcessing() {
    await this._cancelCurrentRequest({ keepWorkspace: true })
    this._hideWorkspace()
  }

  async refreshHistory() {
    await this.refreshQueue()
    this._renderHistory()
  }

  async refreshQueue() {
    if (!this.queueUrlValue) return

    try {
      const response = await fetch(this.queueUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await this._parseJsonResponse(response, "Falha ao carregar a fila de IA.")
      if (!response.ok) throw new Error(data.error || "Falha ao carregar a fila de IA.")

      this.queueRequests = this._mergeQueueSnapshot(data.requests || [])
      this.globalHistoryRequests = this._mergeShellHistorySnapshot(data.recent_history || [])
      this._syncActiveQueueWatchers()
      this._restoreSeedNoteReviewFromQueueSnapshot()
      this._renderQueue()
      if (this.historyDialogTarget?.open) this._renderHistory()
    } catch (_) {
      this._renderQueue()
    }
  }

  selectHistoryFilter(event) {
    this.historyFilter = event.currentTarget.dataset.filterValue || "all"
    this._syncHistoryFilters()
    this._renderHistory()
  }

  handlePromiseEnqueued(detail) {
    this._handlePromiseAiEnqueuedEvent({ detail })
  }

  async historyAction(event) {
    event.preventDefault()
    event.stopPropagation()

    const requestId = event.currentTarget.dataset.requestId
    if (!requestId) return

    const request = this._findRequestById(requestId)
    if (!request) return

    if (request.status === "succeeded") {
      await this._openCompletedRequest(requestId)
      return
    }

    const targetSlug = request.promise_note_slug || request.note_slug
    if (!targetSlug) return

    const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
    if (shell?.navigateTo) await shell.navigateTo(`/notes/${targetSlug}`)
    else if (window.Turbo?.visit) window.Turbo.visit(`/notes/${targetSlug}`)
    else window.location.assign(`/notes/${targetSlug}`)
  }

  async queueAction(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation?.()

    if (event.currentTarget !== event.target && event.target.closest("button")) return

    const requestId = event.currentTarget.dataset.requestId
    const actionType = event.currentTarget.dataset.queueAction
    if (!requestId || !actionType) return

    if (actionType === "retry") {
      await this._retryRequest(requestId)
      return
    }

    if (actionType === "open-result") {
      await this._openCompletedRequest(requestId)
      return
    }

    if (actionType === "dismiss") {
      await this._persistQueueResolution(requestId)
      return
    }

    await this._destroyRequest(requestId)
  }

  handleQueueDragStart(event) {
    if (this.queuePointerDragActive) {
      event.preventDefault()
      return
    }

    const card = event.currentTarget.closest("[data-queue-card='true']")
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
    requestAnimationFrame(() => {
      card.classList.add("opacity-0", "scale-95")
      card.style.visibility = "hidden"
    })
  }

  handleQueueDragOver(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    const targetCard = event.target.closest("[data-queue-card='true'][data-queue-reorderable='true']")
    if (!targetCard || targetCard === this.draggedQueueElement) return

    const rect = targetCard.getBoundingClientRect()
    const insertAfter = event.clientY > rect.top + (rect.height / 2)
    if (insertAfter) targetCard.after(this.queuePlaceholder)
    else targetCard.before(this.queuePlaceholder)
  }

  handleQueueDockDragOver(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    const targetCard = event.target.closest("[data-queue-card='true'][data-queue-reorderable='true']")
    if (targetCard) return

    this.queueDockTarget.append(this.queuePlaceholder)
  }

  async handleQueueDockDrop(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    this.queuePlaceholder.before(this.draggedQueueElement)
    this.draggedQueueElement.classList.remove("hidden")
    this.queuePlaceholder.remove()

    const orderedRequestIds = Array.from(
      this.queueDockTarget.querySelectorAll("[data-queue-card='true'][data-queue-reorderable='true']")
    ).map((card) => card.dataset.requestId).reverse()

    this._cleanupQueueDrag()
    await this._persistQueueOrder(orderedRequestIds)
  }

  async handleQueueDrop(event) {
    if (!this.draggedQueueElement || !this.queuePlaceholder) return

    event.preventDefault()
    this.queuePlaceholder.before(this.draggedQueueElement)
    this.draggedQueueElement.classList.remove("hidden")
    this.queuePlaceholder.remove()

    const orderedRequestIds = Array.from(
      this.queueDockTarget.querySelectorAll("[data-queue-card='true'][data-queue-reorderable='true']")
    ).map((card) => card.dataset.requestId).reverse()

    this._cleanupQueueDrag()
    await this._persistQueueOrder(orderedRequestIds)
  }

  handleQueueDragEnd() {
    if (this.queuePointerDragActive) return
    if (this.draggedQueueElement) {
      this.draggedQueueElement.classList.remove("opacity-0", "scale-95")
      this.draggedQueueElement.style.visibility = ""
    }
    if (this.queuePlaceholder) this.queuePlaceholder.remove()
    this._cleanupQueueDrag()
  }

  handleQueuePointerDown(event) {
    const card = event.currentTarget.closest("[data-queue-card='true']")
    if (!card || card.dataset.queueReorderable !== "true") return
    if (event.button !== 0) return
    if (event.target.closest("button, a, input, select, textarea")) return

    event.preventDefault()

    this.pendingQueuePointerDrag = {
      card,
      requestId: card.dataset.requestId,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      offsetX: event.clientX - card.getBoundingClientRect().left,
      offsetY: event.clientY - card.getBoundingClientRect().top
    }
  }

  handleQueuePointerMove(event) {
    if (this.pendingQueuePointerDrag && !this.queuePointerDragActive) {
      if (event.pointerId !== this.pendingQueuePointerDrag.pointerId) return

      const deltaX = event.clientX - this.pendingQueuePointerDrag.startX
      const deltaY = event.clientY - this.pendingQueuePointerDrag.startY
      if (Math.hypot(deltaX, deltaY) < 6) return

      this._beginQueuePointerDrag(event)
    }

    if (!this.queuePointerDragActive || !this.draggedQueueElement || !this.queuePlaceholder) return
    if (event.pointerId !== this.pendingQueuePointerDrag?.pointerId) return

    event.preventDefault()
    this._positionDraggedQueueElement(event)
    this._moveQueuePlaceholderForPointer(event)
    this._autoScrollQueueDock(event)
  }

  async handleQueuePointerUp(event) {
    if (this.pendingQueuePointerDrag && !this.queuePointerDragActive && event.pointerId === this.pendingQueuePointerDrag.pointerId) {
      this.pendingQueuePointerDrag = null
      return
    }

    if (!this.queuePointerDragActive || event.pointerId !== this.pendingQueuePointerDrag?.pointerId) return

    event.preventDefault()
    await this._completeQueuePointerDrag()
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
        this._resolveQueueRequest(this.lastCompletedRequest?.id)
      } catch (error) {
        window.alert(error.message || "Falha ao criar nota traduzida.")
      } finally {
        this.acceptButtonTarget.disabled = false
        this.acceptButtonTarget.textContent = previousLabel
      }
      return
    }

    if (this.pendingApplyMode === "seed_note_review") {
      await this._persistQueueResolution(this.lastCompletedRequest?.id)
      if (correctedText) editor.setValue(correctedText)
      this._clearPendingSeedNoteReview()
      this.lastCompletedRequest = null
      this._hideWorkspace()
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

    this._resolveQueueRequest(this.lastCompletedRequest?.id)
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

  activateSeedNoteEditing(event) {
    if (this.pendingApplyMode !== "seed_note_review" || !this.seedNotePreviewMode) return

    event.preventDefault()
    this.seedNotePreviewMode = false
    this.proposalDiffTarget.setAttribute("contenteditable", "true")
    this._renderProposal()
    this._placeProposalCaretAtEnd()
  }

  async checkAvailability() {
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await this._parseJsonResponse(response, "Falha ao carregar a configuracao de IA.")

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
    this._editorController()?.exitAiReviewFocusMode?.()
    this._setQueueDockMode("default")
    this._clearProposalStage()
    this._showWorkspace()
    this._clearActiveTrigger()
    this.configNoticeTarget.classList.remove("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
  }

  _showProcessing() {
    this._editorController()?.exitAiReviewFocusMode?.()
    this._setQueueDockMode("default")
    this._clearProposalStage()
    const provider = this.pendingMenu?.providerName || this.aiProvider
    const model = this.pendingMenu?.modelName || this.aiModel

    this._showPreviewShell()
    this.configNoticeTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.remove("flex")
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
    this._editorController()?.exitAiReviewFocusMode?.()
    this._setQueueDockMode("default")
    this._clearProposalStage()
    this._showPreviewShell()
    this.configNoticeTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.processingBoxTarget.classList.remove("flex")
    this.processingErrorTarget.textContent = message
    this.processingErrorTarget.classList.add("hidden")
  }

  _showProposal(corrected) {
    this._editorController()?.exitAiReviewFocusMode?.()
    this._setQueueDockMode("hidden")
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
    if (this.hasDeclineButtonTarget) this.declineButtonTarget.textContent = "Recusar"
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

  _showSeedNoteReview(request) {
    this._clearProposalStage()
    this._editorController()?.enterAiReviewFocusMode?.()
    this._setQueueDockMode("hidden")
    this._storePendingSeedNoteReview(request)
    this._showWorkspace()
    this.configNoticeTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.remove("hidden")
    this.resultBoxTarget.classList.add("flex")
    this.translationMetaTarget.classList.add("hidden")
    if (this.hasDeclineButtonTarget) this.declineButtonTarget.textContent = "Recusar"
    this.acceptButtonTarget.textContent = "Aplicar"
    this.aiSuggestedText = request.corrected || ""
    this.correctedTextTarget.value = this.aiSuggestedText
    this.pendingOriginalText = this.aiSuggestedText
    this.seedNotePreviewMode = false
    this.proposalDiffTarget.setAttribute("contenteditable", "false")
    this.proposalDiffTarget.classList.add("ai-review-proposal--seed-note")
    this.proposalDiffTarget.dataset.placeholder = "Edite o texto da nota criada com IA..."
    this._setSeedNoteSplitLayout(true)
    this._renderProposal()
  }

  _showWorkspace() {
    this.workspaceTarget.classList.remove("hidden")
    this.workspaceTarget.classList.add("flex")
    this.previewShellTarget.classList.add("hidden")
  }

  _showPreviewShell() {
    this.workspaceTarget.classList.add("hidden")
    this.workspaceTarget.classList.remove("flex")
    this.previewShellTarget.classList.remove("hidden")
  }

  _aiStageVisible() {
    return this.hasWorkspaceTarget && !this.workspaceTarget.classList.contains("hidden")
  }

  _hideWorkspace() {
    const clearingSeedNoteReview = this.pendingApplyMode === "seed_note_review"
    this._editorController()?.exitAiReviewFocusMode?.()
    this._setQueueDockMode("default")
    if (clearingSeedNoteReview) this._clearPendingSeedNoteReview()
    this.workspaceTarget.classList.add("hidden")
    this.workspaceTarget.classList.remove("flex")
    this.previewShellTarget.classList.remove("hidden")
    this.configNoticeTarget.classList.add("hidden")
    this.processingBoxTarget.classList.add("hidden")
    this.resultBoxTarget.classList.add("hidden")
    this.translationMetaTarget.classList.add("hidden")
    if (this.hasDeclineButtonTarget) this.declineButtonTarget.textContent = "Fechar"
    this._hideRequestMenu()
    this.pendingMenu = null
    this.pendingApplyMode = "document"
    this.aiSuggestedText = ""
    this.seedNotePreviewMode = false
    this.proposalDiffTarget.setAttribute("contenteditable", "true")
    this.proposalDiffTarget.classList.remove("ai-review-proposal--seed-note")
    this.proposalDiffTarget.classList.remove("ai-review-proposal--seed-note-preview")
    delete this.proposalDiffTarget.dataset.placeholder
    this._setSeedNoteSplitLayout(false)
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
      const response = await fetch(this._queueRequestUrl(requestId), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await this._parseJsonResponse(response, "Falha ao consultar o status da IA.")

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
        this.refreshQueue()
        return
      }

      if (data.status === "failed") throw new Error(data.error || "Falha ao processar com IA.")

      if (data.status === "canceled") {
        this._stopPolling()
        this.currentRequestId = null
        this._hideWorkspace()
        this.refreshHistory()
        this.refreshQueue()
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
    this._markRequestCanceled(requestId)

    try {
      await fetch(this._queueCancelUrl(requestId), {
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
      this.refreshQueue()
      this._clearActiveTrigger()
    }
  }

  _requestUrl(requestId) {
    return this.requestUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _queueRequestUrl(requestId) {
    return this.queueRequestUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _queueCancelUrl(requestId) {
    return this.queueCancelUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _queueResolveUrl(requestId) {
    return this.queueResolveUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  _queueRetryUrl(requestId) {
    return this.queueRetryUrlTemplateValue.replace("__REQUEST_ID__", requestId)
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
    if (this._shouldIgnoreLateRequestUpdate(request)) return

    this._upsertQueueRequest(request)
    this._upsertGlobalHistoryRequest(request)
    if (this._belongsToCurrentNote(request)) this._upsertHistoryRequest(request)
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

    this._upsertQueueRequest({
      id: requestId,
      status: event.detail?.requestStatus || "queued",
      capability: "seed_note",
      provider: event.detail?.provider || "",
      model: event.detail?.model || "",
      note_id: event.detail?.sourceNoteId || null,
      note_slug: event.detail?.sourceNoteSlug || null,
      note_title: this.noteTitleValue || "",
      promise_note_id: event.detail?.noteId || null,
      promise_note_title: event.detail?.noteTitle || "Nota",
      promise_note_slug: event.detail?.noteSlug || null,
      queue_position: Number.MAX_SAFE_INTEGER,
      queue_hidden: false,
      created_at: new Date().toISOString()
    })
    this._upsertGlobalHistoryRequest({
      id: requestId,
      status: event.detail?.requestStatus || "queued",
      capability: "seed_note",
      provider: event.detail?.provider || "",
      model: event.detail?.model || "",
      note_title: this.noteTitleValue || "",
      promise_note_title: event.detail?.noteTitle || "Nota",
      promise_note_slug: event.detail?.noteSlug || null,
      created_at: new Date().toISOString()
    })
    this._renderQueue()
    if (this.historyDialogTarget?.open && this.historyFilter === "shell") this._renderHistory()
    this.refreshQueue()
    this._watchPromiseQueueRequest(requestId)

    try {
      const response = await fetch(this._queueRequestUrl(requestId), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const request = await this._parseJsonResponse(response, "Falha ao carregar a request de IA.")
      if (!response.ok || !request?.id) return

      this._upsertQueueRequest(request)
      this._upsertGlobalHistoryRequest(request)
      if (this._belongsToCurrentNote(request)) this._upsertHistoryRequest(request)
      if (this.historyDialogTarget?.open) this._renderHistory()
      this._renderQueue()
      if (["succeeded", "failed", "canceled"].includes(request.status)) this._stopPromiseQueueWatcher(requestId)
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
    this._syncQueuePolling()
  }

  _syncQueuePolling() {
    if (!this.queueUrlValue) return

    const nextIntervalMs = 3000
    if (this.queuePollTimer && this.queuePollIntervalMs === nextIntervalMs) return

    this._stopQueuePolling()

    this.queuePollTimer = window.setInterval(() => {
      if (document.visibilityState === "hidden") return
      this.refreshQueue()
    }, nextIntervalMs)
    this.queuePollIntervalMs = nextIntervalMs
  }

  _stopQueuePolling() {
    if (!this.queuePollTimer) return

    window.clearInterval(this.queuePollTimer)
    this.queuePollTimer = null
    this.queuePollIntervalMs = null
  }

  _watchPromiseQueueRequest(requestId, attempt = 0) {
    const id = String(requestId)
    if (attempt > 120) {
      this._stopPromiseQueueWatcher(id)
      return
    }

    this._stopPromiseQueueWatcher(id)
    const timer = window.setTimeout(async () => {
      try {
        const response = await fetch(this._queueRequestUrl(id), {
          headers: { Accept: "application/json" },
          credentials: "same-origin"
        })
        const request = await this._parseJsonResponse(response, "Falha ao carregar a request de IA.")
        if (!response.ok || !request?.id) throw new Error("queue_request_missing")

        this._upsertQueueRequest(request)
        this._upsertGlobalHistoryRequest(request)
        if (this._belongsToCurrentNote(request)) this._upsertHistoryRequest(request)
        this._syncActiveQueueWatchers()
        if (this.historyDialogTarget?.open) this._renderHistory()
        this._renderQueue()

        if (["succeeded", "failed", "canceled"].includes(request.status)) {
          this._stopPromiseQueueWatcher(id)
          return
        }
      } catch (_) {
      }

      this._watchPromiseQueueRequest(id, attempt + 1)
    }, attempt === 0 ? 250 : 1500)

    this.promiseQueueWatchers.set(id, timer)
  }

  _stopPromiseQueueWatcher(requestId) {
    const id = String(requestId)
    const timer = this.promiseQueueWatchers.get(id)
    if (!timer) return

    window.clearTimeout(timer)
    this.promiseQueueWatchers.delete(id)
  }

  _stopAllPromiseQueueWatchers() {
    this.promiseQueueWatchers.forEach((timer) => window.clearTimeout(timer))
    this.promiseQueueWatchers.clear()
  }

  _syncActiveQueueWatchers() {
    const activeIds = new Set(
      this.queueRequests
        .filter((request) => ["queued", "running", "retrying"].includes(request.status))
        .map((request) => String(request.id))
    )

    activeIds.forEach((requestId) => {
      if (!this.promiseQueueWatchers.has(requestId)) this._watchPromiseQueueRequest(requestId)
    })

    Array.from(this.promiseQueueWatchers.keys()).forEach((requestId) => {
      if (!activeIds.has(requestId)) this._stopPromiseQueueWatcher(requestId)
    })
  }

  _upsertHistoryRequest(request) {
    if (this._shouldIgnoreLateRequestUpdate(request)) return

    const existingIndex = this.historyRequests.findIndex((item) => String(item.id) === String(request.id))
    if (existingIndex >= 0) this.historyRequests.splice(existingIndex, 1, request)
    else this.historyRequests.unshift(request)

    this.historyRequests = this.historyRequests
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 10)

    this._renderQueue()
  }

  _upsertGlobalHistoryRequest(request) {
    if (this._shouldIgnoreLateRequestUpdate(request)) return

    const existingIndex = this.globalHistoryRequests.findIndex((item) => String(item.id) === String(request.id))
    if (existingIndex >= 0) this.globalHistoryRequests.splice(existingIndex, 1, request)
    else this.globalHistoryRequests.unshift(request)

    this.globalHistoryRequests = this.globalHistoryRequests
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 20)
  }

  _upsertQueueRequest(request) {
    if (this._shouldIgnoreLateRequestUpdate(request)) return

    const existingIndex = this.queueRequests.findIndex((item) => String(item.id) === String(request.id))
    if (existingIndex >= 0) this.queueRequests.splice(existingIndex, 1, request)
    else this.queueRequests.unshift(request)

    this.queueRequests = this.queueRequests
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 30)
  }

  async _retryRequest(requestId) {
    try {
      const response = await fetch(this._queueRetryUrl(requestId), {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        }
      })
      const data = await this._parseJsonResponse(response, "Falha ao reenfileirar request.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao reenfileirar request.")

      this.dismissedQueueRequestIds.delete(String(requestId))
      this.canceledQueueRequestIds.delete(String(requestId))
      this.resolvedQueueRequestIds.delete(String(requestId))
      this._upsertQueueRequest(data)
      this._upsertGlobalHistoryRequest(data)
      if (this._belongsToCurrentNote(data)) this._upsertHistoryRequest(data)
      if (this.historyDialogTarget?.open) this._renderHistory()
      this._renderQueue()
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
    if (this.pendingApplyMode === "seed_note_review") {
      this.proposalDiffTarget.classList.add("ai-review-proposal--seed-note-preview", "preview-prose")
      this.proposalDiffTarget.innerHTML = marked.parse(currentText || "")
      return
    }

    this.proposalDiffTarget.classList.remove("ai-review-proposal--seed-note-preview", "preview-prose")
    const currentAnnotated = this.pendingApplyMode === "seed_note_review"
      ? this._annotateSeedNoteSuggestion(this.aiSuggestedText, currentText)
      : this._annotateCurrentSuggestion(
          this._annotateAiSuggestion(this.pendingOriginalText, this.aiSuggestedText),
          this.aiSuggestedText,
          currentText
        )

    this.proposalDiffTarget.innerHTML = this.pendingApplyMode === "seed_note_review"
      ? this._renderSeedNoteProposal(currentAnnotated)
      : currentAnnotated.map((item) => {
          const escaped = this._escapeHtml(item.value)
          if (item.kind === "ai") return `<span class="rounded bg-emerald-400/15 px-0.5 text-emerald-200">${escaped}</span>`
          if (item.kind === "manual") return `<span class="rounded bg-amber-300/25 px-0.5 text-amber-200">${escaped}</span>`
          return `<span>${escaped}</span>`
        }).join("")
    this._restoreProposalSelection(selection)
  }

  _renderSeedNoteProposal(segments) {
    const lines = this._splitAnnotatedLines(segments)
    if (lines.length === 0) return ""

    return lines.map((line) => {
      const variant = this._seedNoteLineVariant(line)
      const content = line.segments.length === 0
        ? "<br>"
        : line.segments.map((segment) => {
            const escaped = this._escapeHtml(segment.value)
            if (segment.kind === "manual") {
              return `<span class="rounded bg-amber-300/25 px-0.5 text-amber-200">${escaped}</span>`
            }
            return `<span>${escaped}</span>`
          }).join("")

      return `<div class="ai-review-md-line ${variant.className}">${content}</div>`
    }).join("")
  }

  _setSeedNoteSplitLayout(enabled) {
    if (!this.hasProposalPanelsTarget || !this.hasProposalRawPaneTarget || !this.hasProposalPreviewPaneTarget) return

    this.proposalPanelsTarget.classList.toggle("ai-review-proposal-panels--seed-note", enabled)
    this.proposalRawPaneTarget.classList.toggle("hidden", !enabled)
    this.proposalPreviewPaneTarget.classList.toggle("flex-1", enabled)
    this.proposalPreviewPaneTarget.classList.toggle("overflow-y-auto", enabled)
  }

  _splitAnnotatedLines(segments) {
    const lines = []
    let currentLine = []

    segments.forEach((segment) => {
      const parts = String(segment.value || "").split("\n")
      parts.forEach((part, index) => {
        if (part) currentLine.push({ ...segment, value: part })
        if (index < parts.length - 1) {
          lines.push({ segments: currentLine, text: currentLine.map((item) => item.value).join("") })
          currentLine = []
        }
      })
    })

    lines.push({ segments: currentLine, text: currentLine.map((item) => item.value).join("") })
    return lines
  }

  _seedNoteLineVariant(line) {
    const text = (line?.text || "").trimEnd()
    if (!text.trim()) return { className: "ai-review-md-line--blank" }

    const heading = text.match(/^(#{1,6})\s+/)
    if (heading) return { className: `ai-review-md-line--h${heading[1].length}` }
    if (/^\s*[-*+]\s+/.test(text)) return { className: "ai-review-md-line--ul" }
    if (/^\s*\d+\.\s+/.test(text)) return { className: "ai-review-md-line--ol" }
    if (/^>\s+/.test(text)) return { className: "ai-review-md-line--quote" }
    if (/^```/.test(text)) return { className: "ai-review-md-line--codefence" }
    if (/^ {4,}|\t/.test(line?.text || "")) return { className: "ai-review-md-line--code" }
    return { className: "ai-review-md-line--paragraph" }
  }

  _proposalEditorText() {
    return this._serializeProposalNode(this.proposalDiffTarget)
      .replace(/\u00a0/g, " ")
      .replace(/\r\n?/g, "\n")
  }

  _serializeProposalNode(node) {
    if (!node) return ""
    if (node.nodeType === Node.TEXT_NODE) return node.textContent || ""
    if (node.nodeType !== Node.ELEMENT_NODE) return ""
    if (node.tagName === "BR") return "\n"

    const blockTags = new Set([
      "DIV",
      "P",
      "LI",
      "UL",
      "OL",
      "PRE",
      "BLOCKQUOTE",
      "H1",
      "H2",
      "H3",
      "H4",
      "H5",
      "H6"
    ])

    let output = ""
    node.childNodes.forEach((child) => {
      output += this._serializeProposalNode(child)
    })

    if (node !== this.proposalDiffTarget && blockTags.has(node.tagName) && !output.endsWith("\n")) {
      output += "\n"
    }

    return output
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

  _annotateSeedNoteSuggestion(aiSuggestedText, currentText) {
    return this._mergeAnnotated(
      computeWordDiff(aiSuggestedText, currentText).flatMap((item) => {
        if (item.type === "insert") return [{ value: item.value, kind: "manual" }]
        if (item.type === "equal") return [{ value: item.value, kind: "plain" }]
        return []
      })
    )
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

  _placeProposalCaretAtEnd() {
    if (!this.hasProposalDiffTarget) return
    const selection = window.getSelection()
    if (!selection) return

    const range = document.createRange()
    const focus = this._nodeForTextOffset(this._proposalEditorText().length)
    if (!focus) return

    range.setStart(focus.node, focus.offset)
    range.collapse(true)
    selection.removeAllRanges()
    selection.addRange(range)
    this.proposalDiffTarget.focus()
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
    const requests = this._mergeShellHistorySnapshot(this.globalHistoryRequests)

    switch (this.historyFilter) {
      case "queued": return requests.filter((request) => request.status === "queued")
      case "active": return requests.filter((request) => ["running", "retrying"].includes(request.status))
      case "failed": return requests.filter((request) => request.status === "failed")
      case "succeeded": return requests.filter((request) => request.status === "succeeded")
      default: return requests
    }
  }

  _syncHistoryFilters() {
    this.historyFilterTargets.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.filterValue === this.historyFilter)
    })
  }

  _historySummaryLabel(count) {
    return {
      all: `${count} execucoes recentes do shell`,
      queued: `${count} requests na fila`,
      active: `${count} execucoes em processamento`,
      failed: `${count} falhas recentes`,
      succeeded: `${count} execucoes concluidas`
    }[this.historyFilter] || `${count} execucoes recentes`
  }

  _emptyHistoryLabel() {
    return {
      all: "Nenhuma execução recente no shell.",
      queued: "Nenhuma request na fila.",
      active: "Nenhuma execução em processamento.",
      failed: "Nenhuma falha recente.",
      succeeded: "Nenhuma execução concluída."
    }[this.historyFilter] || "Nenhuma execução recente."
  }

  _historyCard(request) {
    const interactive = request.status === "succeeded" || request.promise_note_slug || request.note_slug
    const interactiveClass = interactive ? "cursor-pointer hover:border-[var(--theme-accent)] hover:bg-[var(--theme-bg-hover)]" : ""
    const interactiveAttrs = interactive
      ? `data-request-id="${this._escapeHtml(request.id)}" data-action="click->ai-review#historyAction"`
      : ""
    const provider = request.provider && request.model ? `${request.provider}: ${request.model}` : (request.provider || "IA")
    const noteTitle = request.promise_note_title || request.note_title
    const noteLabel = noteTitle ? `<p class="mt-1 text-xs text-[var(--theme-text-faint)]">${this._escapeHtml(noteTitle)}</p>` : ""
    const statusClass = this._statusClass(request.status)
    const duration = this._durationLabel(request)
    const error = request.error ? `<p class="mt-2 text-xs text-amber-300">${this._escapeHtml(request.error)}</p>` : ""
    const remoteHint = request.remote_hint ? `<p class="mt-2 text-xs ${request.remote_long_job ? "text-amber-300" : "text-[var(--theme-text-secondary)]"}">${this._escapeHtml(request.remote_hint)}</p>` : ""

    return `
      <article class="rounded-lg border border-[var(--theme-border)] bg-[var(--theme-bg-secondary)] p-4 ${interactiveClass}" ${interactiveAttrs}>
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-sm font-semibold text-[var(--theme-text-primary)]">${this._escapeHtml(this._capabilityLabel(request.capability))}</p>
            <p class="text-xs text-[var(--theme-text-muted)]">${this._escapeHtml(provider)}</p>
            ${noteLabel}
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
    if (this.draggedQueueElement) {
      this.queueRenderDeferred = true
      return
    }

    const requests = this._sortedQueueRequests()
      .filter((request) => !this.dismissedQueueRequestIds.has(String(request.id)))
      .filter((request) => !this.resolvedQueueRequestIds.has(String(request.id)))

    if (requests.length === 0) {
      this.queueDockTarget.innerHTML = ""
      this.queueDockTarget.classList.add("hidden")
      return
    }

    if (this.queueDockSuppressed || this._activeSeedNoteReviewRequest()) {
      this.queueDockTarget.innerHTML = ""
      this.queueDockTarget.classList.add("hidden")
      return
    }

    this.queueDockTarget.classList.remove("hidden")
    this.queueDockTarget.innerHTML = requests.map((request) => this._queueCard(request)).join("")
  }

  _queueEligible(request) {
    if (request.queue_hidden) return false

    if (request.capability === "seed_note" && request.status === "succeeded" && !request.promise_note_slug) {
      return false
    }

    return ["queued", "running", "retrying", "failed", "succeeded"].includes(request.status)
  }

  _sortedQueueRequests() {
    return this.queueRequests
      .filter((request) => this._queueEligible(request))
      .sort((left, right) => {
        const leftBucket = this._queueStatusBucket(left)
        const rightBucket = this._queueStatusBucket(right)
        if (leftBucket !== rightBucket) return leftBucket - rightBucket

        if (leftBucket === 0) {
          const leftPos = Number(left.queue_position || 0)
          const rightPos = Number(right.queue_position || 0)
          if (leftPos !== rightPos) return rightPos - leftPos
        }

        if (leftBucket === 1) {
          const leftStarted = new Date(left.started_at || left.created_at || 0)
          const rightStarted = new Date(right.started_at || right.created_at || 0)
          if (leftStarted.getTime() !== rightStarted.getTime()) return rightStarted - leftStarted
        }

        if (leftBucket === 2 || leftBucket === 3) {
          const leftCompleted = new Date(left.completed_at || left.created_at || 0)
          const rightCompleted = new Date(right.completed_at || right.created_at || 0)
          if (leftCompleted.getTime() !== rightCompleted.getTime()) return rightCompleted - leftCompleted
        }

        return new Date(right.created_at || 0) - new Date(left.created_at || 0)
      })
  }

  _queueStatusBucket(request) {
    if (["queued", "retrying"].includes(request.status)) return 0
    if (request.status === "running") return 1
    if (request.status === "failed") return 2
    if (request.status === "succeeded") return 3
    return 4
  }

  _queueCard(request) {
    const presentation = this._queuePresentation(request)
    const noteTitle = request.promise_note_title || request.note_title || "Nota"
    const serviceLabel = presentation.label
    const modelLabel = request.model || request.provider || "IA"
    const borderClass = presentation.borderClass
    const reorderable = presentation.reorderable
    const cardAction = presentation.cardAction
    const cardInteractiveClass = cardAction ? "cursor-pointer hover:bg-[var(--theme-bg-hover)]" : ""
    const actionList = []
    if (reorderable) {
      actionList.push(
        "pointerdown->ai-review#handleQueuePointerDown"
      )
    }
    const actionAttr = actionList.length > 0 ? `data-action="${actionList.join(" ")}"` : ""
    const titleClass = request.status === "failed" ? "text-red-300" : "text-[var(--theme-text-primary)]"
    const dragClass = reorderable ? "cursor-grab active:cursor-grabbing select-none touch-none" : ""
    const requestAttrs = `data-queue-card="true" data-request-id="${this._escapeHtml(request.id)}" data-queue-reorderable="${reorderable}" data-queue-status="${this._escapeHtml(request.status)}"`
    const cardClickAttrs = cardAction
      ? `data-request-id="${this._escapeHtml(request.id)}" data-queue-action="${cardAction}" data-action="click->ai-review#queueAction"`
      : ""
    return `
      <article class="pointer-events-auto ml-auto w-fit min-w-[11rem] max-w-[min(17rem,calc(100vw-1.5rem))] rounded-xl border-2 ${borderClass} bg-[var(--theme-bg-secondary)] px-2.5 py-2 shadow-xl backdrop-blur transition-[transform,opacity,box-shadow] duration-150 ease-out ${cardInteractiveClass} ${dragClass}" ${requestAttrs} ${actionAttr}>
        <div class="flex items-start gap-3">
          <div class="min-w-0 flex-1 ${cardInteractiveClass}" ${cardClickAttrs}>
            <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-[var(--theme-text-faint)]">${this._escapeHtml(serviceLabel)}</p>
            <p class="mt-1 break-words text-sm font-semibold leading-5 ${titleClass}">${this._escapeHtml(noteTitle)}</p>
            <p class="mt-1 break-all text-[11px] text-[var(--theme-text-secondary)]">${this._escapeHtml(modelLabel)}</p>
          </div>
          <div class="flex flex-col items-end gap-2">
            ${presentation.actionButton}
          </div>
        </div>
      </article>
    `
  }

  _queueActionButton(request) {
    if (["queued", "running", "retrying"].includes(request.status)) {
      const label = "X"
      const action = "cancel"
      const title = "Cancelar"

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
        <button type="button"
                title="Desistir"
                aria-label="Desistir"
                class="rounded-full border border-red-700 bg-red-900/40 px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:text-red-400"
                data-request-id="${this._escapeHtml(request.id)}"
                data-queue-action="dismiss"
                data-action="click->ai-review#queueAction">
          X
        </button>
      `
    }

    return ""
  }

  _queueReorderable(request) {
    return ["queued", "retrying"].includes(request.status)
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
        queued: "Melhorar",
        running: "Melhorando",
        retrying: "Melhorando",
        succeeded: "Melhorado",
        failed: "Melhorar"
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

  _queuePresentation(request) {
    return {
      label: this._queueServiceLabel(request),
      borderClass: this._queueBorderClass(request.status),
      reorderable: this._queueReorderable(request),
      cardAction: request.status === "failed" ? "retry" : (request.status === "succeeded" ? "open-result" : ""),
      actionButton: this._queueActionButton(request)
    }
  }

  async _openCompletedRequest(requestId) {
    const request = await this._fetchQueueRequest(requestId)
    if (!request || request.status !== "succeeded") return

    if (request.promise_note_slug) {
      await this._openSeedNoteRequest(request)
      return
    }

    if (request.capability === "translate") {
      await this._openTranslateRequest(request)
      return
    }

    if (["rewrite", "grammar_review"].includes(request.capability)) {
      await this._openSourceReviewRequest(request)
      return
    }

    this._clearPendingCompletedRequestReview()
    this._ensurePreviewVisible()
    this.pendingApplyMode = "document"
    this.pendingOriginalText = request.input_text || this._editor().getValue()
    this.lastCompletedRequest = {
      id: request.id,
      capability: request.capability,
      provider: request.provider,
      model: request.model,
      targetLanguage: request.target_language || this.selectedTargetLanguage()
    }
    this._showProposal(request.corrected || "")
  }

  async _openSeedNoteRequest(request) {
    const path = request.promise_note_slug ? `/notes/${request.promise_note_slug}` : null
    if (path && this._currentNoteSlug() !== request.promise_note_slug) {
      await this._navigateToAiRequestPath(path)
    }

    this.pendingApplyMode = "seed_note_review"
    this.pendingOriginalText = ""
    this.lastCompletedRequest = {
      id: request.id,
      capability: request.capability,
      provider: request.provider,
      model: request.model,
      targetLanguage: request.target_language || this.selectedTargetLanguage()
    }
    this._showSeedNoteReview(request)
  }

  async _openTranslateRequest(request) {
    if (request.translated_note_slug) {
      this._clearPendingCompletedRequestReview()
      await this._navigateToAiRequestPath(`/notes/${request.translated_note_slug}`)
      this._hideWorkspace()
      return
    }

    await this._openSourceReviewRequest(request, { mode: "translation_note" })
  }

  async _openSourceReviewRequest(request, { mode = "document" } = {}) {
    if (request.note_slug && request.note_slug !== this._currentNoteSlug()) {
      this._storePendingCompletedRequestReview(request)
      await this._navigateToAiRequestPath(`/notes/${request.note_slug}`)
      return
    }

    this._clearPendingCompletedRequestReview()
    this._ensurePreviewVisible()
    this.pendingApplyMode = mode
    this.pendingOriginalText = request.input_text || this._editor().getValue()
    this.lastCompletedRequest = {
      id: request.id,
      capability: request.capability,
      provider: request.provider,
      model: request.model,
      targetLanguage: request.target_language || this.selectedTargetLanguage()
    }
    this._showProposal(request.corrected || "")
  }

  _findRequestById(requestId) {
    const id = String(requestId)

    return this.queueRequests.find((item) => String(item.id) === id) ||
      this.globalHistoryRequests.find((item) => String(item.id) === id) ||
      this.historyRequests.find((item) => String(item.id) === id) ||
      null
  }

  _mergeQueueSnapshot(serverRequests) {
    const merged = [...serverRequests]

    this.queueRequests.forEach((request) => {
      if (merged.some((item) => String(item.id) === String(request.id))) return
      if (request.queue_hidden) return
      if (this.promiseQueueWatchers.has(String(request.id)) || ["queued", "running", "retrying"].includes(request.status)) {
        merged.push(request)
      }
    })

    return merged
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 30)
  }

  _mergeShellHistorySnapshot(serverHistory) {
    const merged = [...serverHistory]
    const supplemental = [...this.globalHistoryRequests, ...this.queueRequests]

    supplemental.forEach((request) => {
      if (merged.some((item) => String(item.id) === String(request.id))) return
      if (request.queue_hidden) return
      merged.push(request)
    })

    return merged
      .sort((left, right) => new Date(right.created_at || 0) - new Date(left.created_at || 0))
      .slice(0, 20)
  }

  async _fetchQueueRequest(requestId) {
    const existing = this.queueRequests.find((item) => String(item.id) === String(requestId))
    if (existing?.corrected || existing?.promise_note_slug) return existing

    try {
      const response = await fetch(this._queueRequestUrl(requestId), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await this._parseJsonResponse(response, "Falha ao carregar a request de IA.")
      if (!response.ok || !data?.id) return existing || null
      this._upsertQueueRequest(data)
      this._upsertGlobalHistoryRequest(data)
      if (this._belongsToCurrentNote(data)) this._upsertHistoryRequest(data)
      return data
    } catch (_) {
      return existing || null
    }
  }

  _resolveQueueRequest(requestId) {
    if (!requestId) return

    const requestIdString = String(requestId)
    this._stopPromiseQueueWatcher(requestIdString)
    const queueRequest = this.queueRequests.find((item) => String(item.id) === requestIdString)
    if (queueRequest) queueRequest.queue_hidden = true
    this.resolvedQueueRequestIds.add(requestIdString)
    this.dismissedQueueRequestIds.delete(requestIdString)
    this._renderQueue()
  }

  async _rejectPendingResult() {
    if (!this.lastCompletedRequest?.id) return

    if (this.pendingApplyMode === "seed_note_review" || this.lastCompletedRequest.capability === "seed_note") {
      this._clearPendingSeedNoteReview()
      await this._destroyRequest(this.lastCompletedRequest.id)
      this.lastCompletedRequest = null
      return
    }

    await this._persistQueueResolution(this.lastCompletedRequest.id)
    this.lastCompletedRequest = null
  }

  async _persistQueueResolution(requestId) {
    const requestIdString = String(requestId)
    this.resolvedQueueRequestIds.add(requestIdString)
    this.dismissedQueueRequestIds.add(requestIdString)
    this._renderQueue()

    try {
      const response = await fetch(this._queueResolveUrl(requestId), {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        }
      })
      const data = await this._parseJsonResponse(response, "Falha ao remover item da queue.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao remover item da queue.")

      this._upsertQueueRequest(data)
      this._upsertGlobalHistoryRequest(data)
      if (this._belongsToCurrentNote(data)) this._upsertHistoryRequest(data)
      this._resolveQueueRequest(requestId)
      if (this.historyDialogTarget?.open) this._renderHistory()
      return data
    } catch (error) {
      this.resolvedQueueRequestIds.delete(requestIdString)
      this.dismissedQueueRequestIds.delete(requestIdString)
      this._renderQueue()
      window.alert(error.message || "Falha ao remover item da queue.")
      return null
    }
  }

  _buildQueuePlaceholder(card) {
    const placeholder = document.createElement("div")
    placeholder.className = "pointer-events-none ml-auto rounded-xl border-2 border-dashed border-[var(--theme-border)] bg-transparent opacity-70 transition-[height,transform,opacity] duration-150 ease-out"
    placeholder.dataset.queuePlaceholder = "true"
    placeholder.style.width = `${card.offsetWidth}px`
    placeholder.style.height = `${card.offsetHeight}px`
    return placeholder
  }

  _beginQueuePointerDrag(event) {
    const pending = this.pendingQueuePointerDrag
    if (!pending?.card || pending.card.dataset.queueReorderable !== "true") return

    this.queuePointerDragActive = true
    this.draggedQueueRequestId = pending.requestId
    this.draggedQueueElement = pending.card
    this.queuePlaceholder = this._buildQueuePlaceholder(pending.card)

    pending.card.after(this.queuePlaceholder)

    const rect = pending.card.getBoundingClientRect()
    pending.card.style.width = `${rect.width}px`
    pending.card.style.left = `${rect.left}px`
    pending.card.style.top = `${rect.top}px`
    pending.card.style.position = "fixed"
    pending.card.style.zIndex = "70"
    pending.card.style.pointerEvents = "none"
    pending.card.style.margin = "0"
    pending.card.classList.add("scale-[1.02]", "shadow-2xl", "opacity-90")

    this._positionDraggedQueueElement(event)
  }

  _positionDraggedQueueElement(event) {
    const pending = this.pendingQueuePointerDrag
    if (!pending?.card) return

    pending.card.style.left = `${event.clientX - pending.offsetX}px`
    pending.card.style.top = `${event.clientY - pending.offsetY}px`
  }

  _moveQueuePlaceholderForPointer(event) {
    const targetCard = document.elementFromPoint(event.clientX, event.clientY)?.closest("[data-queue-card='true'][data-queue-reorderable='true']")
    if (!targetCard || targetCard === this.draggedQueueElement) {
      const dockRect = this.queueDockTarget.getBoundingClientRect()
      const insideDock =
        event.clientX >= dockRect.left &&
        event.clientX <= dockRect.right &&
        event.clientY >= dockRect.top &&
        event.clientY <= dockRect.bottom

      if (insideDock) this.queueDockTarget.append(this.queuePlaceholder)
      return
    }

    const rect = targetCard.getBoundingClientRect()
    const insertAfter = event.clientY > rect.top + (rect.height / 2)
    if (insertAfter) targetCard.after(this.queuePlaceholder)
    else targetCard.before(this.queuePlaceholder)
  }

  _autoScrollQueueDock(event) {
    if (!this.hasQueueDockTarget) return

    const rect = this.queueDockTarget.getBoundingClientRect()
    const threshold = 32
    if (event.clientY < rect.top + threshold) this.queueDockTarget.scrollTop -= 18
    else if (event.clientY > rect.bottom - threshold) this.queueDockTarget.scrollTop += 18
  }

  async _completeQueuePointerDrag() {
    if (!this.draggedQueueElement || !this.queuePlaceholder) {
      this._cancelQueuePointerDrag()
      return
    }

    this.queuePlaceholder.before(this.draggedQueueElement)
    this._resetDraggedQueueElementStyles(this.draggedQueueElement)
    this.queuePlaceholder.remove()

    const orderedRequestIds = Array.from(
      this.queueDockTarget.querySelectorAll("[data-queue-card='true'][data-queue-reorderable='true']")
    ).map((card) => card.dataset.requestId).reverse()

    this._cleanupQueueDrag()
    await this._persistQueueOrder(orderedRequestIds)
  }

  _cancelQueuePointerDrag() {
    if (this.draggedQueueElement) this._resetDraggedQueueElementStyles(this.draggedQueueElement)
    if (this.queuePlaceholder) this.queuePlaceholder.remove()
    this._cleanupQueueDrag()
  }

  _resetDraggedQueueElementStyles(card) {
    card.classList.remove("scale-[1.02]", "shadow-2xl", "opacity-90", "opacity-0", "scale-95")
    card.style.visibility = ""
    card.style.width = ""
    card.style.left = ""
    card.style.top = ""
    card.style.position = ""
    card.style.zIndex = ""
    card.style.pointerEvents = ""
    card.style.margin = ""
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
    this.pendingQueuePointerDrag = null
    this.queuePointerDragActive = false
    this.draggedQueueRequestId = null
    this.draggedQueueElement = null
    this.queuePlaceholder = null
    if (this.queueRenderDeferred) {
      this.queueRenderDeferred = false
      this._renderQueue()
    }
  }

  async _persistQueueOrder(orderedRequestIds) {
    if (!orderedRequestIds.length) return

    try {
      const response = await fetch(this.queueReorderUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify({ ordered_request_ids: orderedRequestIds })
      })
      const data = await this._parseJsonResponse(response, "Falha ao reordenar fila.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao reordenar fila.")

      ;(data.requests || []).forEach((request) => {
        this._upsertQueueRequest(request)
        this._upsertGlobalHistoryRequest(request)
        if (this._belongsToCurrentNote(request)) this._upsertHistoryRequest(request)
      })
      if (this.historyDialogTarget?.open) this._renderHistory()
      this._renderQueue()
    } catch (error) {
      window.alert(error.message || "Falha ao reordenar fila.")
      this.refreshQueue()
      if (this.historyDialogTarget?.open) this.refreshHistory()
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
      rewrite: "Melhoria de Markdown",
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

  _currentNoteSlug() {
    return window.location.pathname.match(/^\/notes\/([^/?#]+)/)?.[1] || null
  }

  _activeSeedNoteReviewRequest() {
    const currentSlug = this._currentNoteSlug()
    if (!currentSlug) return null

    return this.queueRequests.find((request) =>
      request.capability === "seed_note" &&
      request.status === "succeeded" &&
      request.promise_note_slug === currentSlug &&
      !request.queue_hidden &&
      !this.resolvedQueueRequestIds.has(String(request.id)) &&
      !this.dismissedQueueRequestIds.has(String(request.id))
    ) || null
  }

  _restoreSeedNoteReviewFromQueueSnapshot() {
    const request = this._activeSeedNoteReviewRequest()
    if (!request) return false

    if (this.pendingApplyMode === "seed_note_review" && String(this.lastCompletedRequest?.id) === String(request.id) && this._aiStageVisible()) {
      this._setQueueDockMode("hidden")
      return true
    }

    this.pendingApplyMode = "seed_note_review"
    this.pendingOriginalText = request.corrected || ""
    this.lastCompletedRequest = {
      id: request.id,
      capability: request.capability || "seed_note",
      provider: request.provider || "",
      model: request.model || "",
      targetLanguage: request.target_language || this.selectedTargetLanguage()
    }
    this._showSeedNoteReview(request)
    return true
  }

  _pendingSeedNoteReviewStorage() {
    try {
      return window.sessionStorage
    } catch (_) {
      return null
    }
  }

  _pendingCompletedRequestReviewStorage() {
    try {
      return window.sessionStorage
    } catch (_) {
      return null
    }
  }

  _storePendingSeedNoteReview(request) {
    if (!request?.id || !request?.promise_note_slug) return

    const storage = this._pendingSeedNoteReviewStorage()
    if (!storage) return

    storage.setItem(PENDING_SEED_NOTE_REVIEW_STORAGE_KEY, JSON.stringify({
      notePath: `/notes/${request.promise_note_slug}`,
      request: {
        id: request.id,
        capability: request.capability || "seed_note",
        provider: request.provider || "",
        model: request.model || "",
        target_language: request.target_language || null,
        corrected: request.corrected || "",
        promise_note_slug: request.promise_note_slug,
        promise_note_title: request.promise_note_title || request.note_title || this.noteTitleValue || "Nota",
        status: request.status || "succeeded"
      }
    }))
  }

  _clearPendingSeedNoteReview() {
    const storage = this._pendingSeedNoteReviewStorage()
    storage?.removeItem(PENDING_SEED_NOTE_REVIEW_STORAGE_KEY)
  }

  _storePendingCompletedRequestReview(request) {
    if (!request?.id || !request?.note_slug) return

    const storage = this._pendingCompletedRequestReviewStorage()
    if (!storage) return

    storage.setItem(PENDING_COMPLETED_REQUEST_REVIEW_STORAGE_KEY, JSON.stringify({
      notePath: `/notes/${request.note_slug}`,
      requestId: request.id
    }))
  }

  _clearPendingCompletedRequestReview() {
    const storage = this._pendingCompletedRequestReviewStorage()
    storage?.removeItem(PENDING_COMPLETED_REQUEST_REVIEW_STORAGE_KEY)
  }

  _restorePendingSeedNoteReview(notePath = window.location.pathname) {
    const storage = this._pendingSeedNoteReviewStorage()
    if (!storage) return false

    try {
      const payload = JSON.parse(storage.getItem(PENDING_SEED_NOTE_REVIEW_STORAGE_KEY) || "null")
      const request = payload?.request
      if (!payload?.notePath || payload.notePath !== notePath || !request?.id || !request?.promise_note_slug) return false

      if (this.pendingApplyMode === "seed_note_review" && String(this.lastCompletedRequest?.id) === String(request.id) && this._aiStageVisible()) {
        return true
      }

      this.pendingApplyMode = "seed_note_review"
      this.pendingOriginalText = request.corrected || ""
      this.lastCompletedRequest = {
        id: request.id,
        capability: request.capability || "seed_note",
        provider: request.provider || "",
        model: request.model || "",
        targetLanguage: request.target_language || this.selectedTargetLanguage()
      }
      this._showSeedNoteReview(request)
      return true
    } catch (_) {
      this._clearPendingSeedNoteReview()
      return false
    }
  }

  async _restorePendingCompletedRequestReview(notePath = window.location.pathname) {
    const storage = this._pendingCompletedRequestReviewStorage()
    if (!storage) return false

    try {
      const payload = JSON.parse(storage.getItem(PENDING_COMPLETED_REQUEST_REVIEW_STORAGE_KEY) || "null")
      if (!payload?.notePath || payload.notePath !== notePath || !payload?.requestId) return false

      this._clearPendingCompletedRequestReview()
      await this._openCompletedRequest(payload.requestId)
      return true
    } catch (_) {
      this._clearPendingCompletedRequestReview()
      return false
    }
  }

  _setQueueDockMode(mode = "default") {
    if (!this.hasQueueDockTarget) return
    this.queueDockSuppressed = mode === "hidden"
    this.queueDockTarget.classList.toggle("ai-review-queue--footer-clearance", mode === "clearance")
    this.queueDockTarget.classList.toggle("hidden", mode === "hidden")
    if (mode === "hidden") this.queueDockTarget.innerHTML = ""
    this._renderQueue()
  }

  _markRequestCanceled(requestId) {
    const requestIdString = String(requestId)
    this.canceledQueueRequestIds.add(requestIdString)
    this._stopPromiseQueueWatcher(requestIdString)
    this._replaceRequestState(this.queueRequests, requestIdString, {
      status: "canceled",
      queue_hidden: true
    })
    this._replaceRequestState(this.historyRequests, requestIdString, {
      status: "canceled"
    })
    this._replaceRequestState(this.globalHistoryRequests, requestIdString, {
      status: "canceled"
    })
    this._renderQueue()
    if (this.historyDialogTarget?.open) this._renderHistory()
  }

  _shouldIgnoreLateRequestUpdate(request) {
    if (!request?.id) return false
    return this.canceledQueueRequestIds.has(String(request.id)) && request.status !== "canceled"
  }

  _replaceRequestState(collection, requestIdString, attributes) {
    const index = collection.findIndex((item) => String(item.id) === requestIdString)
    if (index < 0) return

    collection.splice(index, 1, {
      ...collection[index],
      ...attributes
    })
  }

  _ensurePreviewVisible() {
    this._editorController()?.showPreview?.()
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  async _parseJsonResponse(response, fallbackMessage = "Resposta invalida do servidor.") {
    const contentType = response.headers.get("content-type") || ""
    if (contentType.includes("application/json")) return await response.json()

    const rawBody = await response.text()
    const normalized = rawBody.trim().toLowerCase()
    const htmlLike = normalized.startsWith("<!doctype") || normalized.startsWith("<html")

    if (response.redirected || response.status === 401 || response.status === 403) {
      throw new Error("Sessao expirada ou acesso negado. Recarregue a pagina e tente novamente.")
    }

    if (htmlLike) throw new Error(fallbackMessage)

    const snippet = rawBody.trim().replace(/\s+/g, " ").slice(0, 160)
    throw new Error(snippet || fallbackMessage)
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
    const data = await this._parseJsonResponse(response, "Falha ao criar nota traduzida.")
    if (!response.ok || data.error) throw new Error(data.error || "Falha ao criar nota traduzida.")
    window.location.assign(data.note_url)
  }

  _createTranslatedNoteUrl(requestId) {
    return this.createTranslatedNoteUrlTemplateValue.replace("__REQUEST_ID__", requestId)
  }

  async _destroyRequest(requestId) {
    const requestIdString = String(requestId)
    if (String(this.currentRequestId) === requestIdString) {
      this._stopPolling()
      this.currentRequestId = null
      this._showPreviewShell()
      this._clearActiveTrigger()
    }
    this._stopPromiseQueueWatcher(requestIdString)
    const wasDismissed = this.dismissedQueueRequestIds.has(requestIdString)
    const exitAnimation = this._animateQueueExit(requestIdString)

    this.dismissedQueueRequestIds.add(requestIdString)
    await exitAnimation
    this._renderQueue()

    let data
    try {
      const response = await fetch(this._queueCancelUrl(requestId), {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this._csrfToken()
        }
      })
      data = await this._parseJsonResponse(response, "Falha ao cancelar request de IA.")
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao cancelar request de IA.")
    } catch (error) {
      if (!wasDismissed) this.dismissedQueueRequestIds.delete(requestIdString)
      this.refreshQueue()
      if (this.historyDialogTarget?.open) this.refreshHistory()
      throw error
    }

    const queueRequest = this.queueRequests.find((item) => String(item.id) === String(requestId))
    if (queueRequest) {
      queueRequest.status = data.status
      this._upsertQueueRequest(queueRequest)
      this._upsertGlobalHistoryRequest(queueRequest)
    }

    const historyRequest = this.historyRequests.find((item) => String(item.id) === String(requestId))
    if (historyRequest) {
      historyRequest.status = data.status
      this._upsertHistoryRequest(historyRequest)
    }

    if (data.undone) {
      this.dismissedQueueRequestIds.add(requestIdString)
      this.canceledQueueRequestIds.add(requestIdString)
      await this._restorePromiseSourceAfterUndo(data)
    } else if (data.status === "canceled") {
      this.dismissedQueueRequestIds.add(requestIdString)
      this.canceledQueueRequestIds.add(requestIdString)
    } else if (!wasDismissed) {
      this.dismissedQueueRequestIds.delete(requestIdString)
    }

    if (data.graph_changed) {
      document.dispatchEvent(new CustomEvent("autosave:saved", {
        detail: { kind: "draft", graphChanged: true }
      }))
    }

    if (this.historyDialogTarget?.open) this._renderHistory()
    this._renderQueue()
  }

  _belongsToCurrentNote(request) {
    if (!request?.note_slug || !this.historyUrlValue) return false

    try {
      const url = new URL(this.historyUrlValue, window.location.origin)
      return url.pathname.includes(`/notes/${request.note_slug}/`)
    } catch (_) {
      return false
    }
  }

  _animateQueueExit(requestId) {
    const card = this.queueDockTarget?.querySelector(`[data-request-id="${CSS.escape(String(requestId))}"]`)
    if (!card) return Promise.resolve()

    card.classList.add("pointer-events-none", "opacity-0", "translate-x-2", "scale-95")
    card.style.maxHeight = `${card.offsetHeight}px`
    requestAnimationFrame(() => {
      card.style.maxHeight = "0px"
      card.style.marginTop = "0px"
      card.style.marginBottom = "0px"
      card.style.paddingTop = "0px"
      card.style.paddingBottom = "0px"
      card.style.overflow = "hidden"
    })

    return new Promise((resolve) => window.setTimeout(resolve, 160))
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

  async _restorePromiseSourceAfterUndo(data) {
    const sourceSlug = data?.promise_source_note_slug || data?.note_slug
    const currentSlug = this._currentNoteSlug()

    if (sourceSlug && currentSlug && sourceSlug === currentSlug) {
      this._restorePromiseLinkInEditor(data.promise_note_id, data.restored_content)
      return
    }

    if (sourceSlug) {
      const path = `/notes/${sourceSlug}`
      const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
      if (shell?.navigateTo) await shell.navigateTo(path)
      else if (window.Turbo?.visit) window.Turbo.visit(path)
      else window.location.assign(path)
      return
    }

    if (currentSlug) this._restorePromiseLinkInEditor(data.promise_note_id, data.restored_content)
  }

  _showRequestMenu(trigger, capability, suggestions) {
    if (!trigger || !this.hasRequestMenuTarget) return

    const rect = trigger.getBoundingClientRect()
    this.requestMenuTarget.style.top = `${rect.bottom + window.scrollY + 8}px`
    this.requestMenuTarget.style.left = `${Math.max(12, rect.left + window.scrollX - 12)}px`
    this.requestMenuTitleTarget.textContent = capability === "translate" ? "Escolha idioma e modelo" : "Escolha como processar"
    if (capability === "translate") {
      this.requestMenuListTarget.innerHTML = this._renderTranslateRequestMenu(suggestions)
      this.requestMenuTarget.classList.remove("hidden")
      return
    }

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

  _renderTranslateRequestMenu(suggestions) {
    const languages = [...new Set(
      (this.languageOptionsValue?.length ? this.languageOptionsValue : [this.selectedTargetLanguage()])
        .filter(Boolean)
    )]
    const selectedLanguage = languages.includes(this.preferredTargetLanguage) ? this.preferredTargetLanguage : (languages[0] || "en-US")

    const modelOptions = suggestions.filter((option, index, collection) => {
      return collection.findIndex((candidate) =>
        candidate.provider === option.provider &&
        candidate.model === option.model &&
        candidate.strategy === option.strategy
      ) === index
    })

    return `
      <form class="space-y-3">
        <label class="block">
          <span class="mb-1 block text-xs uppercase tracking-[0.14em] text-[var(--theme-text-faint)]">Idioma</span>
          <select class="w-full rounded-lg border border-[var(--theme-border)] bg-[var(--theme-bg-primary)] px-3 py-2 text-sm text-[var(--theme-text-primary)]"
                  data-ai-review-translate-language>
            ${languages.map((languageCode) => `
              <option value="${this._escapeHtml(languageCode)}" ${languageCode === selectedLanguage ? "selected" : ""}>
                ${this._escapeHtml(this._languageLabel(languageCode))}
              </option>
            `).join("")}
          </select>
        </label>
        <label class="block">
          <span class="mb-1 block text-xs uppercase tracking-[0.14em] text-[var(--theme-text-faint)]">Modelo</span>
          <select class="w-full rounded-lg border border-[var(--theme-border)] bg-[var(--theme-bg-primary)] px-3 py-2 text-sm text-[var(--theme-text-primary)]"
                  data-ai-review-translate-model>
            ${modelOptions.map((option, index) => `
              <option value="${index}"
                      data-provider="${this._escapeHtml(option.provider || "")}"
                      data-model="${this._escapeHtml(option.model || "")}"
                      data-strategy="${this._escapeHtml(option.strategy || "automatic")}">
                ${this._escapeHtml(option.label)}
              </option>
            `).join("")}
          </select>
        </label>
        <button type="submit"
                class="w-full rounded-lg bg-[var(--theme-accent)] px-3 py-2 text-sm font-semibold text-[var(--theme-accent-text)]"
                data-action="click->ai-review#runTranslateOption">
          Traduzir
        </button>
      </form>
    `
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
      return providers.flatMap((option) => this._providerExecutionOptions({
        capability,
        provider: option,
        text,
        targetLanguage: targetLanguage || this.selectedTargetLanguage()
      }))
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

  async _navigateToAiRequestPath(path) {
    if (!path) return

    const shell = this.application.getControllerForElementAndIdentifier(this.element, "note-shell")
    if (shell?.navigateTo) await shell.navigateTo(path)
    else if (window.Turbo?.visit) window.Turbo.visit(path)
    else window.location.assign(path)
  }

  _syncPreferredTargetLanguage() {
    const languages = this.languageOptionsValue || []
    if (languages.includes(this.preferredTargetLanguage)) return
    this.preferredTargetLanguage = languages.includes("en-US") ? "en-US" : (languages[0] || "en-US")
  }

  _handleDocumentClick(event) {
    if (this.hasRequestMenuTarget && !this.requestMenuTarget.classList.contains("hidden")) {
      const insideRequestMenu = this.requestMenuTarget.contains(event.target) || event.target.closest("[data-action*='ai-review#open']")
      if (!insideRequestMenu) this._hideRequestMenu()
    }

    if (this.historyDialogTarget?.open) {
      const insideHistory = this.historyDialogTarget.contains(event.target)
      const onHistoryButton = this.hasHistoryButtonTarget && this.historyButtonTarget.contains(event.target)
      if (!insideHistory && !onHistoryButton) this.closeHistory()
    }
  }

  _positionHistoryDialog(button) {
    if (!button || !this.historyDialogTarget) return

    const rect = button.getBoundingClientRect()
    const viewportWidth = window.innerWidth
    const width = Math.min(Math.round(viewportWidth * 0.92), 672)
    const top = Math.min(rect.bottom + 8, window.innerHeight - 80)
    const left = Math.min(
      Math.max(12, rect.left),
      Math.max(12, viewportWidth - width - 12)
    )

    this.historyDialogTarget.style.position = "fixed"
    this.historyDialogTarget.style.inset = "auto"
    this.historyDialogTarget.style.left = `${left}px`
    this.historyDialogTarget.style.top = `${top}px`
    this.historyDialogTarget.style.margin = "0"
    const height = Math.max(240, window.innerHeight - top - 12)
    this.historyDialogTarget.style.height = `${height}px`
    this.historyDialogTarget.style.maxHeight = `${height}px`
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
