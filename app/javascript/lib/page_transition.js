const TRANSITION_DURATION_MS = 560
const NOTE_GRAPH_RECT_KEY = "neuramd:note-graph-rect"

export function visitWithPageTransition(path, options = {}) {
  if (!path) return

  startPageTransition(options.kind || "graph-to-note")

  window.setTimeout(() => {
    if (window.Turbo?.visit) window.Turbo.visit(path)
    else window.location.href = path
  }, TRANSITION_DURATION_MS)
}

export function submitFormWithPageTransition(form, options = {}) {
  if (!form || form.dataset.transitionSubmitting === "true") return

  form.dataset.transitionSubmitting = "true"
  startPageTransition(options.kind || "auth-to-graph")

  window.setTimeout(() => {
    HTMLFormElement.prototype.submit.call(form)
  }, TRANSITION_DURATION_MS)
}

export function startPageTransition(kind) {
  const body = document.body
  if (!body || body.dataset.transitionLeaving === "true") return

  setTransitionGeometry(body, kind)
  body.dataset.transitionLeaving = "true"
  body.classList.add("nm-transition-leaving")
  if (kind) body.classList.add(`nm-transition--${kind}`)
}

export function pageTransitionDuration() {
  return TRANSITION_DURATION_MS
}

function setTransitionGeometry(body, kind) {
  if (kind === "graph-to-note") {
    const target = loadStoredEmbeddedGraphRect() || estimateEmbeddedGraphRect()
    const viewportCenterX = window.innerWidth / 2
    const viewportCenterY = window.innerHeight / 2
    const targetCenterX = target.left + target.width / 2
    const targetCenterY = target.top + target.height / 2

    body.style.setProperty("--nm-transition-graph-to-note-x", `${targetCenterX - viewportCenterX}px`)
    body.style.setProperty("--nm-transition-graph-to-note-y", `${targetCenterY - viewportCenterY}px`)
    body.style.setProperty("--nm-transition-graph-to-note-scale", `${Math.max(target.height / Math.max(window.innerHeight, 1), 0.36)}`)
    return
  }

  if (kind === "note-to-graph") {
    const graph = document.querySelector(".note-graph-embed")
    if (!graph) return

    const rect = graph.getBoundingClientRect()
    const viewportCenterX = window.innerWidth / 2
    const viewportCenterY = window.innerHeight / 2
    const rectCenterX = rect.left + rect.width / 2
    const rectCenterY = rect.top + rect.height / 2
    const scale = Math.max(window.innerWidth / Math.max(rect.width, 1), window.innerHeight / Math.max(rect.height, 1))

    body.style.setProperty("--nm-transition-note-to-graph-x", `${viewportCenterX - rectCenterX}px`)
    body.style.setProperty("--nm-transition-note-to-graph-y", `${viewportCenterY - rectCenterY}px`)
    body.style.setProperty("--nm-transition-note-to-graph-scale", `${Math.min(scale, 3.4)}`)
  }
}

export function persistNoteGraphRect(element) {
  if (!element || typeof window === "undefined") return

  const rect = element.getBoundingClientRect()
  if (!rect.width || !rect.height) return

  const payload = {
    leftRatio: rect.left / Math.max(window.innerWidth, 1),
    topRatio: rect.top / Math.max(window.innerHeight, 1),
    widthRatio: rect.width / Math.max(window.innerWidth, 1),
    heightRatio: rect.height / Math.max(window.innerHeight, 1),
    viewportWidth: window.innerWidth,
    viewportHeight: window.innerHeight
  }

  window.sessionStorage?.setItem(NOTE_GRAPH_RECT_KEY, JSON.stringify(payload))
}

function estimateEmbeddedGraphRect() {
  const viewportWidth = window.innerWidth
  const viewportHeight = window.innerHeight

  if (viewportWidth <= 720) {
    return {
      left: 16,
      top: viewportHeight * 0.56,
      width: viewportWidth - 32,
      height: Math.min(viewportHeight * 0.28, 320)
    }
  }

  const toolbarHeight = 44
  const sidebarWidth = 220
  const dividerWidth = 1
  const availableWidth = viewportWidth - sidebarWidth - dividerWidth
  const paneWidth = availableWidth / 2
  const previewLeft = sidebarWidth + dividerWidth + paneWidth
  const graphHeight = Math.min(360, viewportHeight * 0.34)
  const top = viewportHeight - graphHeight

  return {
    left: previewLeft,
    top: Math.max(toolbarHeight + 40, top),
    width: paneWidth,
    height: graphHeight
  }
}

function loadStoredEmbeddedGraphRect() {
  if (typeof window === "undefined") return null

  try {
    const raw = window.sessionStorage?.getItem(NOTE_GRAPH_RECT_KEY)
    if (!raw) return null

    const payload = JSON.parse(raw)
    if (!payload) return null

    return {
      left: payload.leftRatio * window.innerWidth,
      top: payload.topRatio * window.innerHeight,
      width: payload.widthRatio * window.innerWidth,
      height: payload.heightRatio * window.innerHeight
    }
  } catch {
    return null
  }
}
