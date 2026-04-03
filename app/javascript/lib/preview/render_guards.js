export class RenderBudgetExceeded extends Error {
  constructor(resource, value) {
    super(`Render budget exceeded: ${resource} = ${value}`)
    this.name = "RenderBudgetExceeded"
    this.resource = resource
    this.value = value
  }
}

export class RenderGuards {
  constructor(opts = {}) {
    this.maxTotalElements = opts.maxTotalElements || 2000
    this.maxRenderTimeMs = opts.maxRenderTimeMs || 5000
    this.maxEmbedCount = opts.maxEmbedCount || 20
    this._startTime = null
    this._embedCount = 0
  }

  startRender() {
    this._startTime = performance.now()
    this._embedCount = 0
  }

  checkTimeout() {
    if (this._startTime === null) return
    const elapsed = performance.now() - this._startTime
    if (elapsed > this.maxRenderTimeMs) {
      throw new RenderBudgetExceeded("timeout", `${Math.round(elapsed)}ms`)
    }
  }

  checkElementCount(outputElement) {
    const count = outputElement.querySelectorAll("*").length
    if (count > this.maxTotalElements) {
      throw new RenderBudgetExceeded("elements", count)
    }
  }

  trackEmbed() {
    this._embedCount++
    if (this._embedCount > this.maxEmbedCount) {
      throw new RenderBudgetExceeded("embeds", this._embedCount)
    }
  }
}
