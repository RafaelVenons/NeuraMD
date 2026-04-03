export function createEmbedRenderer(embedLoader) {
  return {
    name: "embed-loader",
    type: "async",
    selector: ".embed-container.embed-loading",
    dependencies: [],
    limits: { maxElements: 50 },
    fallbackHTML: (el) => {
      const display = el.querySelector(".embed-header")?.textContent || "Embed"
      return `<span class="embed-error">${display}: conteudo nao encontrado</span>`
    },
    async processBatch(elements, context) {
      // Track embed count against budget guards
      if (context.guards) {
        for (let i = 0; i < elements.length; i++) {
          context.guards.trackEmbed()
        }
      }

      await embedLoader.load(
        context.outputElement,
        context.renderVersion,
        context.isStale,
        context.parseMarkdown,
        context.stripBlockMarkers
      )
    }
  }
}
