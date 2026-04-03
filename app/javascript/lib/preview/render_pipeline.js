import { RenderBudgetExceeded } from "lib/preview/render_guards"

const REQUIRED_FIELDS = ["name", "type", "selector", "fallbackHTML"]
const VALID_TYPES = ["sync", "async"]

export function validateRendererContract(def) {
  for (const field of REQUIRED_FIELDS) {
    if (!def[field]) throw new Error(`Renderer contract: missing "${field}"`)
  }
  if (!VALID_TYPES.includes(def.type)) {
    throw new Error(`Renderer contract: type must be "sync" or "async", got "${def.type}"`)
  }
  if (typeof def.fallbackHTML !== "function") {
    throw new Error(`Renderer contract: fallbackHTML must be a function`)
  }
  const hasProcess = typeof def.process === "function"
  const hasBatch = typeof def.processBatch === "function"
  if (!hasProcess && !hasBatch) {
    throw new Error(`Renderer contract: must define process() or processBatch()`)
  }
}

export function topologicalSort(renderers) {
  const graph = new Map()
  const inDegree = new Map()

  for (const r of renderers) {
    graph.set(r.name, [])
    inDegree.set(r.name, 0)
  }

  for (const r of renderers) {
    for (const dep of (r.dependencies || [])) {
      if (!graph.has(dep)) continue
      graph.get(dep).push(r.name)
      inDegree.set(r.name, inDegree.get(r.name) + 1)
    }
  }

  const queue = []
  for (const [name, degree] of inDegree) {
    if (degree === 0) queue.push(name)
  }

  const sorted = []
  while (queue.length > 0) {
    const name = queue.shift()
    sorted.push(name)
    for (const neighbor of graph.get(name)) {
      const newDegree = inDegree.get(neighbor) - 1
      inDegree.set(neighbor, newDegree)
      if (newDegree === 0) queue.push(neighbor)
    }
  }

  if (sorted.length !== renderers.length) {
    throw new Error("Renderer dependency cycle detected")
  }

  const nameToRenderer = new Map(renderers.map(r => [r.name, r]))
  return sorted.map(name => nameToRenderer.get(name))
}

export class RenderPipeline {
  constructor(guards) {
    this._renderers = new Map()
    this._sorted = []
    this._guards = guards || null
  }

  register(rendererDef) {
    validateRendererContract(rendererDef)
    this._renderers.set(rendererDef.name, rendererDef)
    this._sorted = topologicalSort(Array.from(this._renderers.values()))
  }

  async run(outputElement, context) {
    this._guards?.startRender()

    // Cleanup phase
    for (const renderer of this._sorted) {
      if (typeof renderer.cleanup === "function") {
        try { renderer.cleanup(outputElement) } catch (_) { /* ignore cleanup errors */ }
      }
    }

    // Run renderers in topological order, respecting dependencies.
    // Group consecutive sync renderers into a batch, and consecutive
    // independent async renderers into a parallel batch.
    try {
      let i = 0
      while (i < this._sorted.length) {
        if (context.isStale()) return
        this._guards?.checkTimeout()

        const renderer = this._sorted[i]

        if (renderer.type === "sync") {
          this._runSync(renderer, outputElement, context)
          i++
        } else {
          // Collect a batch of independent async renderers
          const batch = [renderer]
          let j = i + 1
          while (j < this._sorted.length && this._sorted[j].type === "async") {
            const deps = this._sorted[j].dependencies || []
            const batchNames = new Set(batch.map(r => r.name))
            const dependsOnBatch = deps.some(d => batchNames.has(d))
            if (dependsOnBatch) break
            batch.push(this._sorted[j])
            j++
          }

          const promises = batch.map(r => this._runAsync(r, outputElement, context))
          await Promise.allSettled(promises)

          this._guards?.checkTimeout()
          this._guards?.checkElementCount(outputElement)
          i = j
        }
      }
    } catch (err) {
      if (err instanceof RenderBudgetExceeded) {
        console.warn(`[RenderPipeline] ${err.message}`)
        this._showBudgetWarning(outputElement, err)
      } else {
        throw err
      }
    }
  }

  _showBudgetWarning(outputElement, err) {
    const existing = outputElement.querySelector(".render-budget-warning")
    if (existing) return

    const warning = document.createElement("div")
    warning.className = "render-budget-warning"
    const labels = {
      timeout: "tempo de renderizacao",
      elements: "numero de elementos",
      embeds: "numero de embeds"
    }
    const label = labels[err.resource] || err.resource
    warning.textContent = `Preview truncado: limite de ${label} atingido.`
    outputElement.appendChild(warning)
  }

  _runSync(renderer, outputElement, context) {
    const elements = this._queryElements(renderer, outputElement)
    if (elements.length === 0) return

    if (typeof renderer.processBatch === "function") {
      try {
        renderer.processBatch(elements, context)
      } catch (error) {
        console.error(`[RenderPipeline] "${renderer.name}" batch failed:`, error)
        elements.forEach(el => this._applyFallback(renderer, el))
      }
      return
    }

    for (const el of elements) {
      try {
        renderer.process(el, context)
      } catch (error) {
        console.error(`[RenderPipeline] "${renderer.name}" failed on element:`, error)
        this._applyFallback(renderer, el)
      }
    }
  }

  async _runAsync(renderer, outputElement, context) {
    const elements = this._queryElements(renderer, outputElement)
    if (elements.length === 0) return

    if (typeof renderer.processBatch === "function") {
      try {
        await renderer.processBatch(elements, context)
      } catch (error) {
        console.error(`[RenderPipeline] "${renderer.name}" batch failed:`, error)
        elements.forEach(el => this._applyFallback(renderer, el))
      }
      return
    }

    const promises = elements.map(async el => {
      try {
        await renderer.process(el, context)
      } catch (error) {
        console.error(`[RenderPipeline] "${renderer.name}" failed on element:`, error)
        this._applyFallback(renderer, el)
      }
    })
    await Promise.allSettled(promises)
  }

  _queryElements(renderer, outputElement) {
    const max = renderer.limits?.maxElements ?? Infinity
    const all = Array.from(outputElement.querySelectorAll(renderer.selector))
    if (all.length > max) {
      console.warn(`[RenderPipeline] "${renderer.name}": ${all.length} elements exceed limit ${max}, truncating`)
      return all.slice(0, max)
    }
    return all
  }

  _applyFallback(renderer, element) {
    try {
      const html = renderer.fallbackHTML(element)
      if (typeof html === "string") {
        const wrapper = document.createElement("div")
        wrapper.innerHTML = html
        element.replaceWith(...wrapper.childNodes)
      }
    } catch (_) {
      // Fallback itself failed — leave element as-is
    }
  }

}
