export const highlightCodeRenderer = {
  name: "highlight-code",
  type: "sync",
  selector: "pre code",
  dependencies: [],
  limits: { maxElements: 200 },
  fallbackHTML: (el) => el.outerHTML,
  process(el) {
    el.classList.add("cm-code-block")
  }
}
