export function resolveNodeDepth(nodeId, focusedNodeId, indexes, maxDepth) {
  if (!focusedNodeId) return 999
  if (nodeId === focusedNodeId) return 0
  if (indexes.neighborDepth1Cache.get(focusedNodeId)?.has(nodeId)) return 1
  if (maxDepth >= 2 && indexes.neighborDepth2Cache.get(focusedNodeId)?.has(nodeId)) return 2
  return 999
}

export function animateCameraToNode(renderer, nodeId) {
  if (!renderer || !nodeId) return
  const node = renderer.getNodeDisplayData(nodeId)
  if (!node) return

  const camera = renderer.getCamera()
  camera.animate(
    {
      x: node.x,
      y: node.y,
      ratio: 0.22
    },
    { duration: 650 }
  )
}
