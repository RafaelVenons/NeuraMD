import graphologyLayout from "graphology-layout"
import forceAtlas2 from "graphology-layout-forceatlas2"
import noverlap from "graphology-layout-noverlap"
import { resolveNodeDepth } from "graph/graph_focus"

export function applyLayout(graph, state, options = {}) {
  if (!graph || graph.order === 0) return
  const rebuild = options.rebuild === true

  if (rebuild || !state.layout.basePositions) {
    graphologyLayout.random.assign(graph)

    const settings = forceAtlas2.inferSettings(graph)
    settings.gravity = 0.08
    settings.scalingRatio = Math.max(settings.scalingRatio || 10, 12)
    settings.slowDown = 2.2

    forceAtlas2.assign(graph, {
      iterations: graph.order < 60 ? 120 : 80,
      settings
    })

    noverlap.assign(graph, {
      maxIterations: 160,
      settings: {
        margin: 14,
        expansion: 1.2,
        gridSize: 20
      }
    })

    state.layout.basePositions = captureNodePositions(graph)
  } else {
    assignNodePositions(graph, state.layout.basePositions)
  }

  compactAroundFocus(graph, state)
  constrainViewportExtent(graph)
  return captureNodePositions(graph)
}

function compactAroundFocus(graph, state) {
  const focusedNodeId = state.ui.focusedNodeId
  if (!focusedNodeId || !graph.hasNode(focusedNodeId)) return

  const focus = graph.getNodeAttributes(focusedNodeId)

  graph.forEachNode((nodeId, attributes) => {
    if (nodeId === focusedNodeId) {
      graph.mergeNodeAttributes(nodeId, { x: focus.x, y: focus.y })
      return
    }

    const dx = attributes.x - focus.x
    const dy = attributes.y - focus.y
    const depth = resolveNodeDepth(nodeId, focusedNodeId, state.indexes, 4)
    const bias = depth === 1 ? 0.72 : depth === 2 ? 0.84 : depth === 3 ? 0.92 : 1

    graph.mergeNodeAttributes(nodeId, {
      x: focus.x + dx * bias,
      y: focus.y + dy * bias
    })
  })
}

function constrainViewportExtent(graph) {
  if (!graph || graph.order === 0) return

  let minX = Infinity
  let maxX = -Infinity
  let minY = Infinity
  let maxY = -Infinity

  graph.forEachNode((_, attributes) => {
    minX = Math.min(minX, attributes.x)
    maxX = Math.max(maxX, attributes.x)
    minY = Math.min(minY, attributes.y)
    maxY = Math.max(maxY, attributes.y)
  })

  const centerX = (minX + maxX) / 2
  const centerY = (minY + maxY) / 2
  const halfWidth = Math.max((maxX - minX) / 2, 0.0001)
  const halfHeight = Math.max((maxY - minY) / 2, 0.0001)
  const aspect = typeof window === "undefined" ? 1.6 : Math.max(window.innerWidth / Math.max(window.innerHeight, 1), 1)
  const maxVertical = 0.125
  const maxHorizontal = maxVertical * aspect
  const scale = Math.min(maxHorizontal / halfWidth, maxVertical / halfHeight, 1)

  graph.forEachNode((nodeId, attributes) => {
    graph.mergeNodeAttributes(nodeId, {
      x: (attributes.x - centerX) * scale,
      y: (attributes.y - centerY) * scale
    })
  })
}

export function captureNodePositions(graph) {
  const positions = new Map()

  graph.forEachNode((nodeId, attributes) => {
    positions.set(nodeId, { x: attributes.x, y: attributes.y })
  })

  return positions
}

export function assignNodePositions(graph, positions) {
  if (!positions) return

  graph.forEachNode((nodeId) => {
    const position = positions.get(nodeId)
    if (!position) return

    graph.mergeNodeAttributes(nodeId, position)
  })
}

export function animateNodePositions(graph, renderer, fromPositions, toPositions, state, options = {}) {
  if (!graph || !renderer || !fromPositions || !toPositions) return

  const duration = options.duration || 760
  const startedAt = performance.now()
  const token = (state.layout.animationToken || 0) + 1
  state.layout.animationToken = token

  const step = (now) => {
    if (state.layout.animationToken !== token) return

    const elapsed = Math.min(1, (now - startedAt) / duration)
    const eased = triangularVelocityEase(elapsed)

    graph.forEachNode((nodeId) => {
      const from = fromPositions.get(nodeId)
      const to = toPositions.get(nodeId)
      if (!from || !to) return

      graph.mergeNodeAttributes(nodeId, {
        x: from.x + (to.x - from.x) * eased,
        y: from.y + (to.y - from.y) * eased
      })
    })

    renderer.refresh()

    if (elapsed < 1) requestAnimationFrame(step)
  }

  requestAnimationFrame(step)
}

function triangularVelocityEase(t) {
  if (t <= 0) return 0
  if (t >= 1) return 1
  if (t < 0.5) return 2 * t * t
  const inverted = 1 - t
  return 1 - 2 * inverted * inverted
}
