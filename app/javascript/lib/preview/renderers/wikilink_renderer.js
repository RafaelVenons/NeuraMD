export function createWikilinkRenderer(validator) {
  return {
    name: "wikilink-validator",
    type: "async",
    selector: "a.wikilink[data-uuid]",
    dependencies: [],
    limits: { maxElements: 200 },
    fallbackHTML: (el) => `<span class="wikilink-broken">${el.textContent || ""}</span>`,
    async processBatch(_elements, context) {
      await validator.validate(context.outputElement, context.renderVersion, context.isStale)
    }
  }
}
