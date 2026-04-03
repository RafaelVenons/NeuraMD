let _katex = null
let _cssInjected = false

const KATEX_CSS_URL = "https://cdn.jsdelivr.net/npm/katex@0.16/dist/katex.min.css"

async function loadKatex() {
  if (!_katex) {
    const mod = await import("katex")
    _katex = mod.default
    injectCss()
  }
  return _katex
}

function injectCss() {
  if (_cssInjected) return
  _cssInjected = true
  const link = document.createElement("link")
  link.rel = "stylesheet"
  link.href = KATEX_CSS_URL
  link.crossOrigin = "anonymous"
  document.head.appendChild(link)
}

function decodeMathSource(encoded) {
  return encoded
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&")
}

export const katexRenderer = {
  name: "katex",
  type: "async",
  selector: ".math-block, .math-inline",
  dependencies: [],
  limits: { maxElements: 200 },
  fallbackHTML: (el) => el.outerHTML,
  async processBatch(elements, context) {
    const katex = await loadKatex()
    if (context.isStale()) return

    for (const el of elements) {
      const encoded = el.getAttribute("data-math")
      if (!encoded) continue

      const src = decodeMathSource(encoded)
      const displayMode = el.classList.contains("math-block")

      try {
        el.innerHTML = katex.renderToString(src, {
          displayMode,
          throwOnError: false,
          output: "htmlAndMathml"
        })
        el.classList.add("math-rendered")
      } catch (err) {
        console.warn(`[katex] render failed for "${src}":`, err)
        // Leave raw source visible as fallback
      }
    }
  }
}
