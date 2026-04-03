let _Chart = null
const _instances = new Map()

async function loadChartJs() {
  if (!_Chart) {
    const mod = await import("https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js")
    _Chart = mod.Chart || mod.default?.Chart || window.Chart
    if (_Chart && typeof _Chart.register === "function") {
      // Auto-register all components for UMD build
      const { registerables } = mod
      if (registerables) _Chart.register(...registerables)
    }
  }
  return _Chart
}

export const chartRenderer = {
  name: "chart",
  type: "async",
  selector: "pre code.language-chart, pre code.language-chartjs",
  dependencies: ["highlight-code"],
  limits: { maxElements: 5 },
  fallbackHTML: (el) => {
    return `<div class="renderer-fallback"><span class="renderer-fallback-label">Grafico indisponivel</span><pre><code>${el.textContent}</code></pre></div>`
  },

  cleanup() {
    for (const [id, chart] of _instances) {
      try { chart.destroy() } catch (_) {}
    }
    _instances.clear()
  },

  async processBatch(elements, context) {
    const Chart = await loadChartJs()
    if (context.isStale() || !Chart) return

    for (const codeEl of elements) {
      if (context.isStale()) return
      const preEl = codeEl.closest("pre")
      if (!preEl) continue

      const src = codeEl.textContent.trim()
      if (!src) continue

      let config
      try {
        config = JSON.parse(src)
      } catch (err) {
        console.warn(`[chart] invalid JSON:`, err)
        const fallback = document.createElement("div")
        fallback.className = "renderer-fallback"
        fallback.innerHTML = `<span class="renderer-fallback-label">Grafico indisponivel: JSON invalido</span><pre><code>${codeEl.textContent}</code></pre>`
        preEl.replaceWith(fallback)
        continue
      }

      try {
        const container = document.createElement("div")
        container.className = "chart-container"
        const canvas = document.createElement("canvas")
        container.appendChild(canvas)
        preEl.replaceWith(container)

        const chartId = `chart-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`
        const chart = new Chart(canvas, config)
        _instances.set(chartId, chart)
      } catch (err) {
        console.warn(`[chart] render failed:`, err)
      }
    }
  }
}
