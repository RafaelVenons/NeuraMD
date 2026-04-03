const BLOCK_ID_RE = /\s\^([a-zA-Z0-9-]+)\s*$/

export const stripBlockMarkersRenderer = {
  name: "strip-block-markers",
  type: "sync",
  selector: "p, li, h1, h2, h3, h4, h5, h6, blockquote",
  dependencies: [],
  limits: { maxElements: 500 },
  fallbackHTML: (el) => el.outerHTML,
  process(el) {
    const match = el.innerHTML.match(BLOCK_ID_RE)
    if (match) {
      el.id = match[1]
      el.innerHTML = el.innerHTML.replace(BLOCK_ID_RE, "")
    }
  }
}
