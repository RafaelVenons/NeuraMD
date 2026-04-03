let _mermaid = null
let _idCounter = 0

async function loadMermaid() {
  if (!_mermaid) {
    const mod = await import("mermaid")
    _mermaid = mod.default
    _mermaid.initialize({ startOnLoad: false, theme: "dark", securityLevel: "strict" })
  }
  return _mermaid
}

export const mermaidRenderer = {
  name: "mermaid",
  type: "async",
  selector: "pre code.language-mermaid",
  dependencies: ["highlight-code"],
  limits: { maxElements: 10 },
  fallbackHTML: (el) => {
    const src = el.textContent || ""
    return `<div class="renderer-fallback"><span class="renderer-fallback-label">Diagrama indisponivel</span><pre><code>${src}</code></pre></div>`
  },
  async processBatch(elements, context) {
    const mermaid = await loadMermaid()
    if (context.isStale()) return

    for (const codeEl of elements) {
      if (context.isStale()) return
      const preEl = codeEl.closest("pre")
      if (!preEl) continue

      const src = codeEl.textContent.trim()
      if (!src) continue

      try {
        const id = `mermaid-${++_idCounter}`
        const { svg } = await mermaid.render(id, src)
        const container = document.createElement("div")
        container.className = "mermaid-container"
        container.innerHTML = svg
        preEl.replaceWith(container)
      } catch (err) {
        console.warn(`[mermaid] render failed:`, err)
        const fallback = document.createElement("div")
        fallback.className = "renderer-fallback"
        fallback.innerHTML = `<span class="renderer-fallback-label">Diagrama indisponivel</span><pre><code>${codeEl.textContent}</code></pre>`
        preEl.replaceWith(fallback)
      }
    }
  }
}
