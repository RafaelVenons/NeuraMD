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
  arrangeFocusDepthRings(graph, state)
  constrainViewportExtent(graph)
  applyManualPositions(graph, state)
  return captureNodePositions(graph)
}

function compactAroundFocus(graph, state) {
  const focusedNodeId = state.ui.focusedNodeId
  if (!focusedNodeId || !graph.hasNode(focusedNodeId)) return

  const focus = graph.getNodeAttributes(focusedNodeId)
  const intensity = resolveFocusLayoutIntensity(state)

  graph.forEachNode((nodeId, attributes) => {
    if (nodeId === focusedNodeId) {
      graph.mergeNodeAttributes(nodeId, { x: focus.x, y: focus.y })
      return
    }

    const dx = attributes.x - focus.x
    const dy = attributes.y - focus.y
    const depth = resolveNodeDepth(nodeId, focusedNodeId, state.indexes, 4)
    const targetBias = depth === 1 ? 0.74 : depth === 2 ? 0.84 : depth === 3 ? 0.92 : 1
    const bias = 1 - ((1 - targetBias) * intensity)

    graph.mergeNodeAttributes(nodeId, {
      x: focus.x + dx * bias,
      y: focus.y + dy * bias
    })
  })
}

function arrangeFocusDepthRings(graph, state) {
  const focusedNodeId = state.ui.focusedNodeId
  if (state.ui.focusDepth < 1 || !focusedNodeId || !graph.hasNode(focusedNodeId)) return

  const focus = graph.getNodeAttributes(focusedNodeId)
  const maxDepth = Math.max(1, Math.min(state.ui.focusDepth, 4))
  const depthOnePlacements = collectDepthOnePlacements(graph, state, focusedNodeId)
  const anchoredNodeIds = [...new Set(depthOnePlacements.map((entry) => entry.nodeId))]

  if (anchoredNodeIds.length === 0) return

  const baseDistance = resolveBaseHierarchyDistance(graph, focus, anchoredNodeIds)
  const intensity = resolveFocusLayoutIntensity(state)
  const ringSpacing = interpolate(baseDistance * 0.56, baseDistance * 0.72, intensity)
  const depthRadii = new Map()

  for (let depth = 1; depth <= maxDepth; depth += 1) {
    depthRadii.set(depth, ringSpacing * depth)
  }

  const bucketMap = new Map()
  depthOnePlacements.forEach((placement) => {
    const bucketKey = `${placement.depth}:${placement.side}:${placement.verticalBand}:${placement.distanceBand}`
    const bucket = bucketMap.get(bucketKey) || []
    if (!bucket.some((entry) => entry.nodeId === placement.nodeId)) bucket.push(placement)
    bucketMap.set(bucketKey, bucket)
  })

  bucketMap.forEach((bucket) => {
    const radius = depthRadii.get(1) || ringSpacing
    positionPlacementBucketOnRing(graph, bucket, focus, radius, intensity)
  })
  enforceRingAngularSpacing(graph, focus, anchoredNodeIds, depthRadii.get(1) || ringSpacing, Math.PI / 18)

  for (let depth = 2; depth <= maxDepth; depth += 1) {
    arrangeOuterDepthRing(graph, state, focus, focusedNodeId, depth, depthRadii.get(depth), ringSpacing)
  }
}

function resolveBaseHierarchyDistance(graph, focus, nodeIds) {
  const distances = nodeIds
    .map((nodeId) => {
      const attributes = graph.getNodeAttributes(nodeId)
      const dx = attributes.x - focus.x
      const dy = attributes.y - focus.y
      return Math.sqrt(dx * dx + dy * dy)
    })
    .filter((distance) => Number.isFinite(distance) && distance > 0)
    .sort((left, right) => left - right)

  const median = distances.length > 0 ? distances[Math.floor(distances.length / 2)] : 0
  return Math.max(median, 0.06)
}

function collectDepthOnePlacements(graph, state, focusedNodeId) {
  const placements = []

  for (const edgeId of state.indexes.outEdgesByNodeId.get(focusedNodeId) || []) {
    const nodeId = graph.target(edgeId)
    if (!state.indexes.neighborDepthCache.get(focusedNodeId)?.[1]?.has(nodeId)) continue

    placements.push({
      nodeId,
      depth: 1,
      ...resolveRelativePlacement(graph.getEdgeAttribute(edgeId, "hierRole") || null, "outbound")
    })
  }

  for (const edgeId of state.indexes.inEdgesByNodeId.get(focusedNodeId) || []) {
    const nodeId = graph.source(edgeId)
    if (!state.indexes.neighborDepthCache.get(focusedNodeId)?.[1]?.has(nodeId)) continue

    placements.push({
      nodeId,
      depth: 1,
      ...resolveRelativePlacement(graph.getEdgeAttribute(edgeId, "hierRole") || null, "inbound")
    })
  }

  return placements
}

function resolveRelativePlacement(role, direction) {
  const side = direction === "outbound" ? "right" : "left"

  if (role === "target_is_parent") {
    return direction === "outbound"
      ? { side, verticalBand: "up", distanceBand: "normal" }
      : { side, verticalBand: "down", distanceBand: "normal" }
  }

  if (role === "target_is_child") {
    return direction === "outbound"
      ? { side, verticalBand: "down", distanceBand: "normal" }
      : { side, verticalBand: "up", distanceBand: "normal" }
  }

  if (role === "same_level") return { side, verticalBand: "mid", distanceBand: "normal" }
  return { side, verticalBand: "mid", distanceBand: "far" }
}

function positionPlacementBucketOnRing(graph, bucket, focus, radius, intensity) {
  if (bucket.length === 0) return

  const [{ side, verticalBand, distanceBand }] = bucket
  const orderedBucket = [...bucket].sort((left, right) => {
    const leftNode = graph.getNodeAttributes(left.nodeId)
    const rightNode = graph.getNodeAttributes(right.nodeId)
    return leftNode.y - rightNode.y
  })

  const centerAngle = angleForBand(side, verticalBand)
  const arcStep = orderedBucket.length > 1
    ? interpolate(Math.PI / 16, Math.PI / 12, intensity)
    : 0
  const bucketRadius = distanceBand === "far" ? radius * 1.26 : radius

  orderedBucket.forEach((entry, index) => {
    const centeredIndex = index - ((orderedBucket.length - 1) / 2)
    const angle = centerAngle + centeredIndex * arcStep
    graph.mergeNodeAttributes(entry.nodeId, {
      x: focus.x + Math.cos(angle) * bucketRadius,
      y: focus.y + Math.sin(angle) * bucketRadius
    })
  })
}

function angleForBand(side, verticalBand) {
  if (side === "right" && verticalBand === "up") return Math.PI / 4
  if (side === "left" && verticalBand === "up") return (3 * Math.PI) / 4
  if (side === "left" && verticalBand === "mid") return Math.PI
  if (side === "right" && verticalBand === "mid") return 0
  if (side === "left" && verticalBand === "down") return (5 * Math.PI) / 4
  return (7 * Math.PI) / 4
}

function arrangeOuterDepthRing(graph, state, focus, focusedNodeId, depth, radius, ringSpacing) {
  const depthNodeIds = [...(state.indexes.neighborDepthCache.get(focusedNodeId)?.[depth] || new Set())]
    .filter((nodeId) => graph.hasNode(nodeId) && resolveNodeDepth(nodeId, focusedNodeId, state.indexes, depth) === depth)

  if (depthNodeIds.length === 0) return

  const orderedNodeIds = depthNodeIds
    .map((nodeId) => ({
      nodeId,
      desiredAngle: resolveAnchorAngle(graph, state, nodeId, focusedNodeId, depth, focus)
    }))
    .sort((left, right) => left.desiredAngle - right.desiredAngle)

  const spacedAngles = distributeAnglesWithMinimumGap(orderedNodeIds.map((entry) => entry.desiredAngle), Math.PI / 18)

  orderedNodeIds.forEach((entry, index) => {
    const angle = spacedAngles[index]
    const distanceBoost = resolveDepthDistanceBoost(graph, state, entry.nodeId, focusedNodeId, depth, ringSpacing)
    graph.mergeNodeAttributes(entry.nodeId, {
      x: focus.x + Math.cos(angle) * (radius + distanceBoost),
      y: focus.y + Math.sin(angle) * (radius + distanceBoost)
    })
  })
}

function resolveAnchorAngle(graph, state, nodeId, focusedNodeId, depth, focus) {
  const parentDepth = depth - 1
  const parentNodeIds = new Set(
    [...(state.indexes.neighborDepthCache.get(focusedNodeId)?.[parentDepth] || new Set())]
      .filter((candidateId) => resolveNodeDepth(candidateId, focusedNodeId, state.indexes, parentDepth) === parentDepth)
  )
  const anchorAngles = []

  for (const edgeId of state.indexes.outEdgesByNodeId.get(nodeId) || []) {
    const targetId = graph.target(edgeId)
    if (parentNodeIds.has(targetId)) anchorAngles.push(angleFromFocus(graph.getNodeAttributes(targetId), focus))
  }

  for (const edgeId of state.indexes.inEdgesByNodeId.get(nodeId) || []) {
    const sourceId = graph.source(edgeId)
    if (parentNodeIds.has(sourceId)) anchorAngles.push(angleFromFocus(graph.getNodeAttributes(sourceId), focus))
  }

  if (anchorAngles.length === 0) {
    return angleFromFocus(graph.getNodeAttributes(nodeId), focus)
  }

  return averageAngles(anchorAngles)
}

function resolveDepthDistanceBoost(graph, state, nodeId, focusedNodeId, depth, ringSpacing) {
  if (depth === 2) {
    const hasNullConnection = connectedToRole(graph, state, nodeId, focusedNodeId, depth, null)
    return hasNullConnection ? ringSpacing * 0.34 : ringSpacing * 0.12
  }

  return ringSpacing * Math.max(0, depth - 2) * 0.12
}

function connectedToRole(graph, state, nodeId, focusedNodeId, depth, role) {
  const parentDepth = depth - 1
  const parentNodeIds = new Set(
    [...(state.indexes.neighborDepthCache.get(focusedNodeId)?.[parentDepth] || new Set())]
      .filter((candidateId) => resolveNodeDepth(candidateId, focusedNodeId, state.indexes, parentDepth) === parentDepth)
  )

  for (const edgeId of state.indexes.outEdgesByNodeId.get(nodeId) || []) {
    const targetId = graph.target(edgeId)
    if (parentNodeIds.has(targetId) && (graph.getEdgeAttribute(edgeId, "hierRole") || null) === role) return true
  }

  for (const edgeId of state.indexes.inEdgesByNodeId.get(nodeId) || []) {
    const sourceId = graph.source(edgeId)
    if (parentNodeIds.has(sourceId) && (graph.getEdgeAttribute(edgeId, "hierRole") || null) === role) return true
  }

  return false
}

function angleFromFocus(node, focus) {
  return Math.atan2(node.y - focus.y, node.x - focus.x)
}

function averageAngles(angles) {
  const vector = angles.reduce((accumulator, angle) => ({
    x: accumulator.x + Math.cos(angle),
    y: accumulator.y + Math.sin(angle)
  }), { x: 0, y: 0 })

  return Math.atan2(vector.y, vector.x)
}

function distributeAnglesWithMinimumGap(angles, minGap) {
  if (angles.length <= 1) return angles

  const normalized = angles.map((angle) => normalizeAngle(angle))
  const result = [...normalized]

  for (let index = 1; index < result.length; index += 1) {
    result[index] = Math.max(result[index], result[index - 1] + minGap)
  }

  for (let index = result.length - 2; index >= 0; index -= 1) {
    result[index] = Math.min(result[index], result[index + 1] - minGap)
  }

  for (let index = 0; index < result.length; index += 1) {
    const delta = normalized[index] - result[index]
    if (delta === 0) continue

    const previousAngle = index > 0 ? result[index - 1] : -Infinity
    const nextAngle = index < result.length - 1 ? result[index + 1] : Infinity
    result[index] = clamp(normalized[index], previousAngle + minGap, nextAngle - minGap)
  }

  return result
}

function enforceRingAngularSpacing(graph, focus, nodeIds, radius, minGap) {
  if (!nodeIds || nodeIds.length < 2) return

  const entries = nodeIds
    .filter((nodeId) => graph.hasNode(nodeId))
    .map((nodeId) => {
      const node = graph.getNodeAttributes(nodeId)
      const dx = node.x - focus.x
      const dy = node.y - focus.y
      return {
        nodeId,
        angle: normalizeAngle(angleFromFocus(node, focus)),
        radius: Math.max(Math.sqrt(dx * dx + dy * dy), radius)
      }
    })
    .sort((left, right) => left.angle - right.angle)

  if (entries.length < 2) return

  for (let index = 1; index < entries.length; index += 1) {
    if (entries[index].angle - entries[index - 1].angle < minGap) {
      entries[index].angle = entries[index - 1].angle + minGap
    }
  }

  const totalSpan = entries[entries.length - 1].angle - entries[0].angle
  const fullCircle = Math.PI * 2

  if (totalSpan > fullCircle - minGap) {
    const compressedGap = (fullCircle - minGap) / Math.max(entries.length - 1, 1)
    entries.forEach((entry, index) => {
      entry.angle = entries[0].angle + index * compressedGap
    })
  }

  entries.forEach((entry) => {
    graph.mergeNodeAttributes(entry.nodeId, {
      x: focus.x + Math.cos(entry.angle) * entry.radius,
      y: focus.y + Math.sin(entry.angle) * entry.radius
    })
  })
}

function normalizeAngle(angle) {
  const fullCircle = Math.PI * 2
  let normalized = angle % fullCircle
  if (normalized < 0) normalized += fullCircle
  return normalized
}

function clamp(value, min, max) {
  if (min > max) return value
  return Math.min(Math.max(value, min), max)
}

function applyManualPositions(graph, state) {
  if (!state.layout.manualPositions || state.layout.manualPositions.size === 0) return

  state.layout.manualPositions.forEach((position, nodeId) => {
    if (!graph.hasNode(nodeId)) return
    graph.mergeNodeAttributes(nodeId, position)
  })
}

function resolveFocusLayoutIntensity(state) {
  if (state.ui.focusDepth === 1) return 0.78
  if (state.ui.focusDepth === 2) return 0.68
  return 0.44
}

function interpolate(min, max, t) {
  return min + ((max - min) * t)
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
