import graphologyLayout from "graphology-layout"
import forceAtlas2 from "graphology-layout-forceatlas2"
import noverlap from "graphology-layout-noverlap"

export function applyLayout(graph, state) {
  if (!graph || graph.order === 0) return

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

  compactAroundFocus(graph, state)
}

function compactAroundFocus(graph, state) {
  const focusedNodeId = state.ui.focusedNodeId
  if (!focusedNodeId || !graph.hasNode(focusedNodeId)) return

  const focus = graph.getNodeAttributes(focusedNodeId)
  const depth1 = state.indexes.neighborDepth1Cache.get(focusedNodeId) || new Set()
  const depth2 = state.indexes.neighborDepth2Cache.get(focusedNodeId) || new Set()

  graph.forEachNode((nodeId, attributes) => {
    if (nodeId === focusedNodeId) {
      graph.mergeNodeAttributes(nodeId, { x: focus.x, y: focus.y })
      return
    }

    const dx = attributes.x - focus.x
    const dy = attributes.y - focus.y
    const bias = depth1.has(nodeId) ? 0.42 : depth2.has(nodeId) ? 0.74 : 1

    graph.mergeNodeAttributes(nodeId, {
      x: focus.x + dx * bias,
      y: focus.y + dy * bias
    })
  })
}
