import { Controller } from "@hotwired/stimulus"
import { computeWordDiff } from "lib/diff_utils"

export default class extends Controller {
  static targets = [
    "dialog",
    "configNotice",
    "diffContent",
    "originalText",
    "correctedText",
    "correctedDiff",
    "providerBadge",
    "editToggle",
    "processingOverlay",
    "processingProvider",
    "scopeLabel"
  ]

  static values = {
    statusUrl: String,
    reviewUrl: String
  }

  connect() {
    this.aiEnabled = false
    this.aiProvider = null
    this.aiModel = null
    this.pendingApplyMode = "document"
    this.pendingOriginalText = ""
    this.checkAvailability()
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

  async open(capability) {
    await this.checkAvailability()

    if (!this.aiEnabled) {
      this._showConfigNotice()
      return
    }

    const editor = this._editor()
    const selection = editor.getSelection()
    const documentMarkdown = editor.getValue()
    const text = selection || documentMarkdown

    if (!text.trim()) {
      window.alert("Nenhum texto para processar.")
      return
    }

    this.pendingApplyMode = selection ? "selection" : "document"
    this.pendingOriginalText = text
    this.scopeLabelTarget.textContent = selection ? "Trecho selecionado" : "Documento inteiro"

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
          text,
          document_markdown: documentMarkdown
        })
      })

      const data = await response.json()
      if (!response.ok || data.error) throw new Error(data.error || "Falha ao processar com IA.")

      this._showDiff(data.original, data.corrected, data.provider, data.model)
    } catch (error) {
      window.alert(error.message || "Falha ao processar com IA.")
    } finally {
      this._hideProcessing()
    }
  }

  close() {
    this.dialogTarget.close()
  }

  accept() {
    const editor = this._editor()
    const correctedText = this.correctedTextTarget.value

    if (this.pendingApplyMode === "selection") {
      editor.replaceSelection(correctedText)
    } else {
      editor.setValue(correctedText)
    }

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
    } catch (_) {
      this.aiEnabled = false
      this.aiProvider = null
      this.aiModel = null
    }
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

    this.dialogTarget.showModal()
  }

  _showProcessing() {
    this.processingProviderTarget.textContent = this.aiProvider && this.aiModel ? `${this.aiProvider}: ${this.aiModel}` : "AI"
    this.processingOverlayTarget.classList.remove("hidden")
  }

  _hideProcessing() {
    this.processingOverlayTarget.classList.add("hidden")
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

  _escapeHtml(text) {
    return text
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
}
