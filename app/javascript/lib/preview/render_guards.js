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
    this.maxTotalElements = opts.maxTotalElements || 5000
    this.maxRenderTimeMs = opts.maxRenderTimeMs || 15000
    this.maxEmbedCount = opts.maxEmbedCount || 50
    this.strict = opts.strict ?? false
    this._startTime = null
    this._embedCount = 0
    this._warned = new Set()
  }

  startRender() {
    this._startTime = performance.now()
    this._embedCount = 0
    this._warned.clear()
  }

  checkTimeout() {
    if (this._startTime === null) return
    const elapsed = performance.now() - this._startTime
    if (elapsed > this.maxRenderTimeMs) {
      if (this.strict) throw new RenderBudgetExceeded("timeout", `${Math.round(elapsed)}ms`)
      this._warnOnce("timeout", `${Math.round(elapsed)}ms`)
    }
  }

  checkElementCount(outputElement) {
    const count = outputElement.querySelectorAll("*").length
    if (count > this.maxTotalElements) {
      if (this.strict) throw new RenderBudgetExceeded("elements", count)
      this._warnOnce("elements", count)
    }
  }

  trackEmbed() {
    this._embedCount++
    if (this._embedCount > this.maxEmbedCount) {
      if (this.strict) throw new RenderBudgetExceeded("embeds", this._embedCount)
      this._warnOnce("embeds", this._embedCount)
    }
  }

  _warnOnce(resource, value) {
    if (this._warned.has(resource)) return
    this._warned.add(resource)
    console.warn(`[RenderGuards] soft limit: ${resource} = ${value}`)
  }
}
