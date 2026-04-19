import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

let sharedConsumer = null
const getConsumer = () => {
  if (!sharedConsumer) sharedConsumer = createConsumer()
  return sharedConsumer
}

export default class extends Controller {
  static targets = ["terminal", "startButton", "stopButton", "status", "command"]
  static values = {
    tentacleId: String,
    startUrl: String,
    stopUrl: String,
    csrf: String
  }

  connect() {
    this.terminal = new Terminal({
      convertEol: true,
      cursorBlink: true,
      fontSize: 13,
      fontFamily: "JetBrains Mono, ui-monospace, monospace",
      theme: { background: "#0b0b0b" }
    })
    this.fitAddon = new FitAddon()
    this.terminal.loadAddon(this.fitAddon)
    this.terminal.open(this.terminalTarget)
    requestAnimationFrame(() => this.fitAddon.fit())

    this.terminal.onData((data) => {
      if (!this.subscription) return
      this.subscription.perform("input", { data })
    })

    this.resizeObserver = new ResizeObserver(() => this.handleResize())
    this.resizeObserver.observe(this.terminalTarget)
  }

  disconnect() {
    this.unsubscribe()
    this.resizeObserver?.disconnect()
    this.terminal?.dispose()
  }

  async start() {
    const command = this.hasCommandTarget ? this.commandTarget.value : "bash"
    this.setStatus("starting…")

    try {
      const res = await fetch(this.startUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ command })
      })
      if (!res.ok) throw new Error(`start failed (${res.status})`)
      const body = await res.json()
      this.terminal.writeln(`\x1b[90m[tentacle ${body.tentacle_id} — pid ${body.pid} — ${body.cwd}]\x1b[0m`)
      this.subscribe()
      this.setStatus("running")
      this.startButtonTarget.hidden = true
      this.stopButtonTarget.hidden = false
    } catch (err) {
      console.error(err)
      this.setStatus("error")
      this.terminal.writeln(`\x1b[31m[error: ${err.message}]\x1b[0m`)
    }
  }

  async stop() {
    this.setStatus("stopping…")
    try {
      const res = await fetch(this.stopUrlValue, {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        }
      })
      if (!res.ok) throw new Error(`stop failed (${res.status})`)
    } catch (err) {
      console.error(err)
    } finally {
      this.unsubscribe()
      this.setStatus("stopped")
      this.startButtonTarget.hidden = false
      this.stopButtonTarget.hidden = true
    }
  }

  subscribe() {
    if (this.subscription) return
    const consumer = getConsumer()
    this.subscription = consumer.subscriptions.create(
      { channel: "TentacleChannel", tentacle_id: this.tentacleIdValue },
      {
        connected: () => this.handleResize(),
        received: (msg) => this.handleMessage(msg)
      }
    )
  }

  unsubscribe() {
    if (!this.subscription) return
    this.subscription.unsubscribe()
    this.subscription = null
  }

  handleMessage(msg) {
    if (!msg) return
    if (msg.type === "output") {
      this.terminal.write(msg.data)
    } else if (msg.type === "exit") {
      const tail = msg.status == null ? "closed" : `exit ${msg.status}`
      this.terminal.writeln(`\r\n\x1b[90m[${tail}]\x1b[0m`)
      this.setStatus("stopped")
      this.startButtonTarget.hidden = false
      this.stopButtonTarget.hidden = true
      this.unsubscribe()
    }
  }

  handleResize() {
    if (!this.terminal) return
    this.fitAddon.fit()
    if (!this.subscription) return
    const { cols, rows } = this.terminal
    this.subscription.perform("resize", { cols, rows })
  }

  setStatus(label) {
    if (this.hasStatusTarget) this.statusTarget.textContent = label
  }
}
