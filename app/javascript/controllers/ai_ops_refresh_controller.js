import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "status"]

  static values = {
    refreshUrl: String,
    intervalMs: { type: Number, default: 10000 },
    activeCount: { type: Number, default: 0 }
  }

  connect() {
    this.activeCount = this.activeCountValue
    this.realtimeConnected = false
    this.deadline = null
    this.refreshTimer = null
    this.countdownTimer = null
    this.streamObserver = null

    this.observeStreamSource()
    if (this.activeCount > 0) {
      this.start()
    } else {
      this.renderPaused()
    }
  }

  disconnect() {
    this.streamObserver?.disconnect()
    this.stop()
  }

  start() {
    this.stop()
    this.deadline = Date.now() + this.intervalMsValue
    this.renderActive()

    this.countdownTimer = window.setInterval(() => {
      this.renderActive()
    }, 1000)

    this.refreshTimer = window.setTimeout(() => {
      if (document.visibilityState === "hidden") {
        this.start()
        return
      }

      this.refresh()
    }, this.intervalMsValue)
  }

  async refresh() {
    try {
      const response = await fetch(this.refreshUrlValue, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
      const html = await response.text()
      if (!response.ok) throw new Error("refresh failed")

      const fragment = this.extractFragment(html)
      if (!fragment) throw new Error("fragment missing")

      this.contentTarget.innerHTML = fragment.innerHTML
      this.activeCount = Number(fragment.dataset.activeCount || 0)

      if (this.activeCount > 0) {
        this.start()
      } else {
        this.stop()
        this.renderPaused()
      }
    } catch (_) {
      this.stop()
      this.renderPaused()
    }
  }

  stop() {
    if (this.refreshTimer) {
      window.clearTimeout(this.refreshTimer)
      this.refreshTimer = null
    }

    if (this.countdownTimer) {
      window.clearInterval(this.countdownTimer)
      this.countdownTimer = null
    }
  }

  renderActive() {
    if (!this.hasStatusTarget) return

    const remainingSeconds = Math.max(Math.ceil((this.deadline - Date.now()) / 1000), 0)
    if (this.realtimeConnected) {
      this.statusTarget.textContent = `Tempo real conectado • refresh de apoio em ${remainingSeconds}s`
    } else {
      this.statusTarget.textContent = `Tempo real indisponível • fallback polling em ${remainingSeconds}s`
    }
  }

  renderPaused() {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = this.realtimeConnected ? "Tempo real conectado • polling pausado" : "Tempo real indisponível • polling pausado"
  }

  observeStreamSource() {
    const source = document.querySelector("turbo-cable-stream-source")
    if (!source) {
      this.realtimeConnected = false
      return
    }

    this.realtimeConnected = source.hasAttribute("connected")
    this.renderConnectionState()

    this.streamObserver = new MutationObserver(() => {
      this.realtimeConnected = source.hasAttribute("connected")
      this.renderConnectionState()
    })

    this.streamObserver.observe(source, { attributes: true, attributeFilter: ["connected"] })
  }

  renderConnectionState() {
    if (this.activeCount > 0) {
      this.renderActive()
    } else {
      this.renderPaused()
    }
  }

  extractFragment(html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    return template.content.querySelector("[data-ai-ops-refresh-fragment]")
  }
}
