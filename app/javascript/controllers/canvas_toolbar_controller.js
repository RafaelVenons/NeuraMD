import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  selectTool(event) {
    const tool = event.params.tool
    if (!tool) return

    // Update active state on buttons
    this.element.querySelectorAll(".cv-tool-btn").forEach(btn => {
      btn.classList.toggle("is-active", btn.dataset.canvasToolbarToolParam === tool)
    })

    // Notify canvas controller via custom event
    this.dispatch("toolSelected", { detail: { tool }, bubbles: true })

    // Also directly call setTool on sibling canvas controller
    const canvasEl = this.element.closest("[data-controller~='canvas']")
    if (canvasEl) {
      const canvasController = this.application.getControllerForElementAndIdentifier(canvasEl, "canvas")
      if (canvasController) canvasController.setTool({ detail: { tool } })
    }
  }

  // Listen for keyboard-triggered tool changes from canvas controller
  handleToolChanged(event) {
    const tool = event.detail?.tool
    if (!tool) return
    this.element.querySelectorAll(".cv-tool-btn").forEach(btn => {
      btn.classList.toggle("is-active", btn.dataset.canvasToolbarToolParam === tool)
    })
  }
}
