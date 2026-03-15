export function resolveNodeDepth(nodeId, focusedNodeId, indexes, maxDepth) {
  if (!focusedNodeId) return 999
  if (nodeId === focusedNodeId) return 0
  const cache = indexes.neighborDepthCache.get(focusedNodeId)

  for (let depth = 1; depth <= maxDepth; depth += 1) {
    if (cache?.[depth]?.has(nodeId)) return depth
  }

  return 999
}

export function animateCameraToNode(renderer, state) {
  if (!renderer || !state.ui.focusedNodeId) return

  const targetState = resolveCameraTargetState(renderer, state)
  if (!targetState) return

  const camera = renderer.getCamera()
  camera.animate(
    targetState,
    {
      duration: 760,
      easing: (t) => {
        if (t < 0.5) return 2 * t * t
        const inverted = 1 - t
        return 1 - 2 * inverted * inverted
      }
    }
  )

  // Recenter near the end so the camera follows the final node positions too.
  setTimeout(() => {
    const settledState = resolveCameraTargetState(renderer, state)
    if (!settledState) return

    camera.animate(settledState, {
      duration: 240,
      easing: (t) => t
    })
  }, 620)
}

function resolveCameraTargetState(renderer, state) {
  const focusIds = []
  const maxDepth = state.ui.focusDepth

  state.graph.forEachNode((nodeId) => {
    const depth = resolveNodeDepth(nodeId, state.ui.focusedNodeId, state.indexes, maxDepth)
    if (nodeId === state.ui.focusedNodeId || depth <= maxDepth) focusIds.push(nodeId)
  })

  if (focusIds.length === 0) return null

  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity

  focusIds.forEach((nodeId) => {
    const point = renderer.getNodeDisplayData(nodeId)
    if (!point) return

    minX = Math.min(minX, point.x)
    minY = Math.min(minY, point.y)
    maxX = Math.max(maxX, point.x)
    maxY = Math.max(maxY, point.y)
  })

  if (!Number.isFinite(minX) || !Number.isFinite(minY)) return null

  const span = Math.max(maxX - minX, maxY - minY)

  return {
    x: (minX + maxX) / 2,
    y: (minY + maxY) / 2,
    ratio: Math.max(0.48, Math.min(0.9, span * 2.0 + 0.16))
  }
}
