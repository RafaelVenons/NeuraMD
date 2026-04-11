import graphologyLayout from "graphology-layout"
import forceAtlas2 from "graphology-layout-forceatlas2"
import noverlap from "graphology-layout-noverlap"
import { resolveNodeDepth } from "graph/graph_focus"
import { relaxForces, isLayoutDegenerate } from "graph/graph_force_relax"

export function applyLayout(graph, state, options = {}) {
  if (!graph || graph.order === 0) return
  const rebuild = options.rebuild === true

  if (rebuild || !state.layout.basePositions) {
    graphologyLayout.random.assign(graph)

    const settings = forceAtlas2.inferSettings(graph)
    settings.gravity = 1.2
    settings.strongGravityMode = true
    settings.scalingRatio = Math.max(settings.scalingRatio || 10, 14)
    settings.slowDown = 2.4
    settings.barnesHutOptimize = graph.order > 80

    forceAtlas2.assign(graph, {
      iterations: graph.order < 60 ? 160 : 100,
      settings
    })

    noverlap.assign(graph, {
      maxIterations: 160,
      settings: {
        margin: 12,
        expansion: 1.15,
        gridSize: 20
      }
    })

    state.layout.basePositions = captureNodePositions(graph)
  } else {
    assignNodePositions(graph, state.layout.basePositions)
  }

  compactAroundFocus(graph, state)
  arrangeFocusDepthRings(graph, state)
  constrainViewportExtent(graph, state.ui.focusedNodeId)
  applyManualPositions(graph, state)

  if (isLayoutDegenerate(graph)) {
    relaxForces(graph, { iterations: 80, temperature: 0.18 })
    constrainViewportExtent(graph, state.ui.focusedNodeId)
  }

  return captureNodePositions(graph)
}

/**
 * Position depth-2 nodes in semi-arcs around their depth-1 parents,
 * always on the external side (further from focus than the parent).
 */
function arrangeSemiRings(graph, state, focus, focusedNodeId, ringOneRadius, depthOneNodeIdSet) {
  const depth2NodeIds = [...(state.indexes.neighborDepthCache.get(focusedNodeId)?.[2] || new Set())]
    .filter((id) => graph.hasNode(id) && resolveNodeDepth(id, focusedNodeId, state.indexes, 2) === 2)

  if (depth2NodeIds.length === 0) return

  // Group depth-2 nodes by their closest depth-1 parent
  const parentGroups = new Map()
  for (const d1Id of depthOneNodeIdSet) parentGroups.set(d1Id, [])

  for (const d2Id of depth2NodeIds) {
    const bestParent = findClosestDepthOneParent(graph, state, d2Id, depthOneNodeIdSet, focus)
    if (bestParent && parentGroups.has(bestParent)) {
      parentGroups.get(bestParent).push(d2Id)
    }
  }

  const semiRingRadius = ringOneRadius * 1.8
  const ARC_HALF_SPAN = Math.PI / 3 // ±60°

  for (const [parentId, children] of parentGroups) {
    if (children.length === 0) continue

    const parentAngle = angleFromFocus(graph.getNodeAttributes(parentId), focus)

    if (children.length === 1) {
      graph.mergeNodeAttributes(children[0], {
        x: focus.x + Math.cos(parentAngle) * semiRingRadius,
        y: focus.y + Math.sin(parentAngle) * semiRingRadius
      })
      continue
    }

    const arcStep = (ARC_HALF_SPAN * 2) / (children.length - 1)
    const startAngle = parentAngle - ARC_HALF_SPAN

    children.forEach((childId, i) => {
      const angle = startAngle + arcStep * i
      graph.mergeNodeAttributes(childId, {
        x: focus.x + Math.cos(angle) * semiRingRadius,
        y: focus.y + Math.sin(angle) * semiRingRadius
      })
    })
  }
}

function findClosestDepthOneParent(graph, state, d2NodeId, depthOneNodeIdSet, focus) {
  let bestParent = null
  let bestAngleDist = Infinity
  const d2Angle = normalizeAngle(angleFromFocus(graph.getNodeAttributes(d2NodeId), focus))

  for (const edgeId of state.indexes.outEdgesByNodeId.get(d2NodeId) || []) {
    const targetId = graph.target(edgeId)
    if (depthOneNodeIdSet.has(targetId)) {
      const dist = angularDistance(d2Angle, normalizeAngle(angleFromFocus(graph.getNodeAttributes(targetId), focus)))
      if (dist < bestAngleDist) { bestAngleDist = dist; bestParent = targetId }
    }
  }

  for (const edgeId of state.indexes.inEdgesByNodeId.get(d2NodeId) || []) {
    const sourceId = graph.source(edgeId)
    if (depthOneNodeIdSet.has(sourceId)) {
      const dist = angularDistance(d2Angle, normalizeAngle(angleFromFocus(graph.getNodeAttributes(sourceId), focus)))
      if (dist < bestAngleDist) { bestAngleDist = dist; bestParent = sourceId }
    }
  }

  return bestParent
}

function angularDistance(a, b) {
  const diff = Math.abs(a - b)
  return Math.min(diff, Math.PI * 2 - diff)
}

function compactAroundFocus(graph, state) {
  const focusedNodeId = state.ui.focusedNodeId
  if (!focusedNodeId || !graph.hasNode(focusedNodeId)) return

  const focus = graph.getNodeAttributes(focusedNodeId)
  const intensity = resolveFocusLayoutIntensity(state)
  const originX = focus.x
  const originY = focus.y

  // Move focus to origin so rings are centered
  graph.mergeNodeAttributes(focusedNodeId, { x: 0, y: 0 })

  graph.forEachNode((nodeId, attributes) => {
    if (nodeId === focusedNodeId) return

    const dx = attributes.x - originX
    const dy = attributes.y - originY
    const depth = resolveNodeDepth(nodeId, focusedNodeId, state.indexes, 4)
    const targetBias = depth === 1 ? 0.74 : depth === 2 ? 0.84 : depth === 3 ? 0.92 : 1
    const bias = 1 - ((1 - targetBias) * intensity)

    graph.mergeNodeAttributes(nodeId, {
      x: dx * bias,
      y: dy * bias
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
  const ringSpacing = interpolate(baseDistance * 0.42, baseDistance * 0.56, intensity)
  const depthRadii = new Map()

  for (let depth = 1; depth <= maxDepth; depth += 1) {
    depthRadii.set(depth, ringSpacing * depth)
  }

  const ringOneRadius = depthRadii.get(1) || ringSpacing
  const depthOneNodeIdSet = new Set(anchoredNodeIds)

  // --- Barycentric ordering for depth-1 ring (minimizes edge crossings) ---
  const barycentricEntries = computeBarycentricOrder(graph, state, focusedNodeId, anchoredNodeIds, focus, maxDepth)
  const minGap = anchoredNodeIds.length > 1
    ? Math.min(Math.PI * 2 / anchoredNodeIds.length, Math.PI / 8)
    : 0
  const spacedAngles = distributeAnglesWithMinimumGap(
    barycentricEntries.map((entry) => entry.angle),
    minGap
  )

  // Distribute depth-1 across sub-rings when crowded (interleave radii)
  const subRingCount = Math.max(1, Math.ceil(anchoredNodeIds.length / 8))

  barycentricEntries.forEach((entry, index) => {
    let radius = ringOneRadius
    if (subRingCount > 1) {
      const subRing = index % subRingCount
      const radiusFactor = 0.82 + 0.36 * (subRing / (subRingCount - 1))
      radius = ringOneRadius * radiusFactor
    }
    graph.mergeNodeAttributes(entry.nodeId, {
      x: focus.x + Math.cos(spacedAngles[index]) * radius,
      y: focus.y + Math.sin(spacedAngles[index]) * radius
    })
  })

  // --- Depth-2: semi-rings around their depth-1 parents (external only) ---
  if (maxDepth >= 2) {
    arrangeSemiRings(graph, state, focus, focusedNodeId, ringOneRadius, depthOneNodeIdSet)
  }

  // --- Arrange outer depth rings (depth 3+) ---
  for (let depth = 3; depth <= maxDepth; depth += 1) {
    arrangeOuterDepthRing(graph, state, focus, focusedNodeId, depth, depthRadii.get(depth), ringSpacing)
  }

  // --- Exclusion zone: push depth-3+ nodes outside ring-2 buffer ---
  const exclusionRadius = ringOneRadius * 2.2
  enforceExclusionZone(graph, state, focus, focusedNodeId, depthOneNodeIdSet, exclusionRadius)
}

/**
 * Barycentric ordering: for each depth-1 node, compute the angle where its
 * depth-2 connections pull it, then sort by that angle. This naturally minimizes
 * edge crossings between the ring and outer nodes.
 *
 * Falls back to hierarchy-based angles for nodes with no depth-2 connections.
 */
function computeBarycentricOrder(graph, state, focusedNodeId, depthOneNodeIds, focus, maxDepth) {
  const depth2NodeIds = maxDepth >= 2
    ? new Set([...(state.indexes.neighborDepthCache.get(focusedNodeId)?.[2] || new Set())]
        .filter((id) => graph.hasNode(id) && resolveNodeDepth(id, focusedNodeId, state.indexes, 2) === 2))
    : new Set()

  const entries = depthOneNodeIds.map((nodeId) => {
    const pullAngles = []

    // Collect angles from depth-2 neighbors of this depth-1 node
    for (const edgeId of state.indexes.outEdgesByNodeId.get(nodeId) || []) {
      const targetId = graph.target(edgeId)
      if (depth2NodeIds.has(targetId)) {
        pullAngles.push(angleFromFocus(graph.getNodeAttributes(targetId), focus))
      }
    }
    for (const edgeId of state.indexes.inEdgesByNodeId.get(nodeId) || []) {
      const sourceId = graph.source(edgeId)
      if (depth2NodeIds.has(sourceId)) {
        pullAngles.push(angleFromFocus(graph.getNodeAttributes(sourceId), focus))
      }
    }

    let angle
    if (pullAngles.length > 0) {
      angle = averageAngles(pullAngles)
    } else {
      // Fallback: use hierarchy-based placement angle
      angle = resolveHierarchyAngle(graph, state, nodeId, focusedNodeId, focus)
    }

    return { nodeId, angle: normalizeAngle(angle) }
  })

  entries.sort((a, b) => a.angle - b.angle)
  return entries
}

/**
 * Resolve a hierarchy-based angle for a depth-1 node (fallback when no depth-2 pull).
 */
function resolveHierarchyAngle(graph, state, nodeId, focusedNodeId, focus) {
  for (const edgeId of state.indexes.outEdgesByNodeId.get(focusedNodeId) || []) {
    if (graph.target(edgeId) === nodeId) {
      const placement = resolveRelativePlacement(graph.getEdgeAttribute(edgeId, "hierRole") || null, "outbound")
      return angleForBand(placement.side, placement.verticalBand)
    }
  }
  for (const edgeId of state.indexes.inEdgesByNodeId.get(focusedNodeId) || []) {
    if (graph.source(edgeId) === nodeId) {
      const placement = resolveRelativePlacement(graph.getEdgeAttribute(edgeId, "hierRole") || null, "inbound")
      return angleForBand(placement.side, placement.verticalBand)
    }
  }
  return angleFromFocus(graph.getNodeAttributes(nodeId), focus)
}

/**
 * Enforce exclusion zone: push any depth-2+ node that's inside the ring-1 buffer
 * radially outward so the ring region stays clean.
 */
function enforceExclusionZone(graph, state, focus, focusedNodeId, depthOneNodeIdSet, exclusionRadius) {
  graph.forEachNode((nodeId, attrs) => {
    if (nodeId === focusedNodeId || depthOneNodeIdSet.has(nodeId)) return

    const dx = attrs.x - focus.x
    const dy = attrs.y - focus.y
    const dist = Math.sqrt(dx * dx + dy * dy)

    if (dist < exclusionRadius && dist > 0.0001) {
      const pushRadius = exclusionRadius * 1.1
      const angle = Math.atan2(dy, dx)
      graph.mergeNodeAttributes(nodeId, {
        x: focus.x + Math.cos(angle) * pushRadius,
        y: focus.y + Math.sin(angle) * pushRadius
      })
    } else if (dist <= 0.0001) {
      // Overlapping with focus — push to a random angle outside exclusion
      const angle = Math.PI * 0.25
      graph.mergeNodeAttributes(nodeId, {
        x: focus.x + Math.cos(angle) * exclusionRadius * 1.2,
        y: focus.y + Math.sin(angle) * exclusionRadius * 1.2
      })
    }
  })
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
  if (role === "next_in_sequence") return { side, verticalBand: "mid", distanceBand: "normal" }
  return { side: "free", verticalBand: "soft", distanceBand: "far", placementMode: "soft" }
}

function angleForBand(side, verticalBand) {
  if (side === "right" && verticalBand === "up") return (7 * Math.PI) / 4
  if (side === "left" && verticalBand === "up") return (5 * Math.PI) / 4
  if (side === "left" && verticalBand === "mid") return Math.PI
  if (side === "right" && verticalBand === "mid") return 0
  if (side === "left" && verticalBand === "down") return (3 * Math.PI) / 4
  return Math.PI / 4
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
  if (state.ui.focusDepth === 1) return 0.9
  if (state.ui.focusDepth === 2) return 0.82
  return 0.58
}

function interpolate(min, max, t) {
  return min + ((max - min) * t)
}

function constrainViewportExtent(graph, focusedNodeId) {
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

  // Center on focus node when in focus mode (not bounding box center)
  let centerX, centerY
  if (focusedNodeId && graph.hasNode(focusedNodeId)) {
    const focus = graph.getNodeAttributes(focusedNodeId)
    centerX = focus.x
    centerY = focus.y
  } else {
    centerX = (minX + maxX) / 2
    centerY = (minY + maxY) / 2
  }
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
