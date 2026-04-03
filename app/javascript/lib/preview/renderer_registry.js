import { validateRendererContract } from "lib/preview/render_pipeline"

/**
 * RendererRegistry — central catalog of all registered renderers.
 *
 * Each renderer must satisfy the contract validated by validateRendererContract:
 *   - name: string (unique identifier)
 *   - type: "sync" | "async"
 *   - selector: string (CSS selector)
 *   - fallbackHTML: function(element) → string
 *   - process(element, context) and/or processBatch(elements, context)
 *
 * Optional:
 *   - dependencies: string[] (renderer names that must run first)
 *   - limits: { maxElements: number }
 *   - cleanup: function(outputElement)
 */
export class RendererRegistry {
  static _renderers = new Map()

  static register(rendererDef) {
    validateRendererContract(rendererDef)
    this._renderers.set(rendererDef.name, rendererDef)
  }

  static lookup(name) {
    return this._renderers.get(name) || null
  }

  static registered(name) {
    return this._renderers.has(name)
  }

  static names() {
    return Array.from(this._renderers.keys())
  }

  static all() {
    return Array.from(this._renderers.values())
  }
}
