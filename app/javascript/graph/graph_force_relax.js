/**
 * Force-directed relaxation for degenerate graph layouts.
 *
 * Repulsion between all vertex pairs: F = k_repel / d
 * Attraction along edges:             F = k_attract * log(d / idealLength)
 *
 * Taylor approximation for log near ratio ≈ 1 (avoids Math.log for common case).
 * Extreme-case priority: skips repulsion pairs in the "comfortable" distance band.
 */

const COMFORTABLE_LOW = 0.4
const COMFORTABLE_HIGH = 2.5
const OVERLAP_JITTER = 0.3
const MIN_DISTANCE = 0.0001

export function relaxForces(graph, options = {}) {
  const iterations = options.iterations || 60
  const initialTemperature = options.temperature || 0.15

  const nodeIds = []
  const positions = new Map()

  graph.forEachNode((id, attrs) => {
    nodeIds.push(id)
    positions.set(id, { x: attrs.x, y: attrs.y, fx: 0, fy: 0 })
  })

  const n = nodeIds.length
  if (n < 2) return

  const idealLength = resolveIdealEdgeLength(graph, positions)
  const kRepel = idealLength * idealLength * 0.6
  const kAttract = 0.12
  const comfortLow = idealLength * COMFORTABLE_LOW
  const comfortHigh = idealLength * COMFORTABLE_HIGH

  for (let iter = 0; iter < iterations; iter++) {
    const cooling = 1 - iter / iterations
    const temperature = initialTemperature * cooling * cooling

    resetForces(positions)
    applyRepulsion(nodeIds, positions, kRepel, comfortLow, idealLength, n)
    applyEdgeAttraction(graph, positions, kAttract, idealLength)
    integrateForces(positions, temperature, idealLength)
  }

  positions.forEach((p, id) => {
    graph.mergeNodeAttributes(id, { x: p.x, y: p.y })
  })
}

function resolveIdealEdgeLength(graph, positions) {
  const lengths = []

  graph.forEachEdge((_, _attrs, src, dst) => {
    const sp = positions.get(src)
    const dp = positions.get(dst)
    if (!sp || !dp) return

    const d = fastHypot(dp.x - sp.x, dp.y - sp.y)
    if (d > MIN_DISTANCE) lengths.push(d)
  })

  if (lengths.length === 0) return 0.05

  lengths.sort((a, b) => a - b)
  return Math.max(lengths[Math.floor(lengths.length / 2)], 0.01)
}

function resetForces(positions) {
  positions.forEach((p) => { p.fx = 0; p.fy = 0 })
}

function applyRepulsion(nodeIds, positions, kRepel, comfortLow, idealLength, n) {
  for (let i = 0; i < n; i++) {
    const pi = positions.get(nodeIds[i])
    for (let j = i + 1; j < n; j++) {
      const pj = positions.get(nodeIds[j])
      const dx = pj.x - pi.x
      const dy = pj.y - pi.y
      const d = fastHypot(dx, dy)

      if (d < MIN_DISTANCE) {
        // Overlapping nodes — random jitter push
        const angle = (i * 7 + j * 13) % 628 / 100  // deterministic pseudo-random
        const force = idealLength * OVERLAP_JITTER
        const jx = Math.cos(angle) * force
        const jy = Math.sin(angle) * force
        pi.fx -= jx; pi.fy -= jy
        pj.fx += jx; pj.fy += jy
        continue
      }

      // Skip comfortable-range pairs for performance
      if (d > comfortLow && d < idealLength * COMFORTABLE_HIGH) continue

      // F = k / d  (repulsion, inverse distance)
      // For very close nodes: stronger push. For far nodes: weak but present.
      const invD = fastInverse(d)
      const force = kRepel * invD
      const fx = dx * invD * force
      const fy = dy * invD * force
      pi.fx -= fx; pi.fy -= fy
      pj.fx += fx; pj.fy += fy
    }
  }
}

function applyEdgeAttraction(graph, positions, kAttract, idealLength) {
  const invIdeal = fastInverse(idealLength)

  graph.forEachEdge((_, _attrs, src, dst) => {
    const sp = positions.get(src)
    const dp = positions.get(dst)
    if (!sp || !dp) return

    const dx = dp.x - sp.x
    const dy = dp.y - sp.y
    const d = fastHypot(dx, dy)
    if (d < MIN_DISTANCE) return

    const ratio = d * invIdeal
    const logApprox = approxLog(ratio)
    const force = kAttract * logApprox
    const invD = fastInverse(d)
    const fx = dx * invD * force
    const fy = dy * invD * force

    sp.fx += fx; sp.fy += fy
    dp.fx -= fx; dp.fy -= fy
  })
}

function integrateForces(positions, temperature, idealLength) {
  const maxDisplacement = temperature * idealLength

  positions.forEach((p) => {
    const fm = fastHypot(p.fx, p.fy)
    if (fm < MIN_DISTANCE) return

    const capped = Math.min(fm, maxDisplacement)
    const scale = capped / fm
    p.x += p.fx * scale
    p.y += p.fy * scale
  })
}

// --- Fast math approximations ---

/**
 * Taylor approximation for log(x):
 *   Near 1: log(1+ε) ≈ ε - ε²/2 + ε³/3
 *   Far from 1: fall back to Math.log
 */
function approxLog(x) {
  if (x <= 0) return -10

  if (x > 0.5 && x < 2.0) {
    // Taylor series around x=1: log(x) = (x-1) - (x-1)²/2 + (x-1)³/3
    const eps = x - 1
    return eps - eps * eps * 0.5 + eps * eps * eps * 0.333
  }

  // For extreme ratios, use native log (these are the cases we care about most)
  return Math.log(x)
}

/**
 * Fast 1/x — direct division. JS engines optimize this well.
 * Named for clarity and to centralize the approximation point.
 */
function fastInverse(x) {
  return 1 / x
}

/**
 * Fast hypotenuse — avoids Math.hypot overhead for hot paths.
 * Math.sqrt is heavily optimized in V8/SpiderMonkey.
 */
function fastHypot(dx, dy) {
  return Math.sqrt(dx * dx + dy * dy)
}

/**
 * Detect degenerate layout: returns true if nodes are severely overlapping
 * or edge lengths have extreme variance.
 */
export function isLayoutDegenerate(graph) {
  if (!graph || graph.order < 3) return false

  const positions = []
  graph.forEachNode((_, attrs) => {
    positions.push({ x: attrs.x, y: attrs.y })
  })

  // Check pairwise distances for overlap
  let overlapCount = 0
  let pairCount = 0
  const n = positions.length

  for (let i = 0; i < n && i < 20; i++) {
    for (let j = i + 1; j < n && j < 20; j++) {
      const d = fastHypot(positions[j].x - positions[i].x, positions[j].y - positions[i].y)
      pairCount++
      if (d < 0.001) overlapCount++
    }
  }

  if (pairCount > 0 && overlapCount / pairCount > 0.3) return true

  // Check edge length variance
  const edgeLengths = []
  graph.forEachEdge((_, _attrs, src, dst) => {
    const s = graph.getNodeAttributes(src)
    const d = graph.getNodeAttributes(dst)
    edgeLengths.push(fastHypot(d.x - s.x, d.y - s.y))
  })

  if (edgeLengths.length < 2) return false

  edgeLengths.sort((a, b) => a - b)
  const minEdge = Math.max(edgeLengths[0], 0.0001)
  const maxEdge = edgeLengths[edgeLengths.length - 1]

  return maxEdge / minEdge > 100
}
