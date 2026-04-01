const { test, expect } = require("@playwright/test")
const { execFileSync } = require("node:child_process")
const path = require("node:path")
const { signIn } = require("./helpers/session")

function loadScenario() {
  const cwd = path.resolve(__dirname, "..")
  const ruby = `
    # Pick a note with at least 4 outgoing links (good focus candidate)
    focus_note = Note.active
      .joins("INNER JOIN note_links ON note_links.src_note_id = notes.id AND note_links.active = true")
      .group("notes.id")
      .having("COUNT(note_links.id) >= 4")
      .order(Arel.sql("COUNT(note_links.id) DESC"))
      .first

    raise "No note with >= 4 outgoing links" unless focus_note

    payload = {
      credentials: {
        email: "rafael.santos.garcia@hotmail.com",
        password: "password123"
      },
      focus_slug: focus_note.slug,
      focus_title: focus_note.title
    }

    puts payload.to_json
  `

  return JSON.parse(execFileSync("bin/rails", ["runner", ruby], {
    cwd,
    env: { ...process.env, RAILS_ENV: "development" },
    encoding: "utf8"
  }).trim())
}

/**
 * Extract node positions from sigma via the debug handle.
 * Returns { nodes: [{ id, x, y, depth }], focusId }
 */
async function extractGraphState(page) {
  return page.evaluate(() => {
    const ctrl = window.__graphDebug
    if (!ctrl?.state?.graph) return null

    const graph = ctrl.state.graph
    const focusId = ctrl.state.ui.focusedNodeId
    const indexes = ctrl.state.indexes
    const nodes = []

    graph.forEachNode((nodeId, attrs) => {
      let depth = 999
      if (focusId) {
        if (nodeId === focusId) depth = 0
        else {
          const cache = indexes?.neighborDepthCache?.get(focusId)
          for (let d = 1; d <= 4; d++) {
            if (cache?.[d]?.has(nodeId)) { depth = d; break }
          }
        }
      }

      nodes.push({
        id: nodeId,
        x: attrs.x,
        y: attrs.y,
        depth,
        hidden: attrs.hidden === true
      })
    })

    return { nodes, focusId }
  })
}

function distanceTo(node, cx, cy) {
  return Math.sqrt((node.x - cx) ** 2 + (node.y - cy) ** 2)
}

function medianOf(values) {
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

test.describe("Graph density and layout", () => {
  let scenario

  test.beforeAll(() => {
    scenario = loadScenario()
  })

  test("full graph has uniform density without hollow center", async ({ page }) => {
    await signIn(page, scenario.credentials)
    await page.goto("/graph", { waitUntil: "domcontentloaded" })

    // Wait for graph to render
    await page.waitForFunction(() => {
      const ctrl = window.__graphDebug
      return ctrl?.state?.graph?.order > 0
    }, { timeout: 15000 })

    // Let layout settle
    await page.waitForTimeout(2000)

    const state = await extractGraphState(page)
    expect(state).not.toBeNull()
    expect(state.nodes.length).toBeGreaterThan(10)

    const visibleNodes = state.nodes.filter((n) => !n.hidden)
    const xs = visibleNodes.map((n) => n.x)
    const ys = visibleNodes.map((n) => n.y)
    const cx = (Math.min(...xs) + Math.max(...xs)) / 2
    const cy = (Math.min(...ys) + Math.max(...ys)) / 2

    const distances = visibleNodes.map((n) => distanceTo(n, cx, cy))
    const maxDist = Math.max(...distances)

    // Divide into inner third and outer two-thirds
    const innerThreshold = maxDist / 3
    const innerCount = distances.filter((d) => d <= innerThreshold).length
    const outerCount = distances.filter((d) => d > innerThreshold).length

    // Inner third should have at least 10% of nodes (not hollow)
    const innerRatio = innerCount / visibleNodes.length
    expect(innerRatio).toBeGreaterThan(0.10)

    // Outer region should not have more than 80% (not a thin ring)
    const outerRatio = outerCount / visibleNodes.length
    expect(outerRatio).toBeLessThan(0.80)
  })

  test("focus mode places depth-1 inner and depth-2 outer", async ({ page }) => {
    await signIn(page, scenario.credentials)
    await page.goto("/graph", { waitUntil: "domcontentloaded" })

    // Wait for graph to render
    await page.waitForFunction(() => {
      const ctrl = window.__graphDebug
      return ctrl?.state?.graph?.order > 0
    }, { timeout: 15000 })

    await page.waitForTimeout(2000)

    // Enter focus mode by double-clicking the target note
    await page.evaluate((slug) => {
      const ctrl = window.__graphDebug
      const graph = ctrl.state.graph
      let targetId = null

      graph.forEachNode((nodeId, attrs) => {
        if (attrs.slug === slug) targetId = nodeId
      })

      if (targetId) ctrl.enterFocusMode(targetId)
    }, scenario.focus_slug)

    // Let focus layout settle
    await page.waitForTimeout(2000)

    const state = await extractGraphState(page)
    expect(state).not.toBeNull()
    expect(state.focusId).not.toBeNull()

    const focusNode = state.nodes.find((n) => n.id === state.focusId)
    expect(focusNode).toBeDefined()

    const depth1Nodes = state.nodes.filter((n) => n.depth === 1 && !n.hidden)
    const depth2Nodes = state.nodes.filter((n) => n.depth === 2 && !n.hidden)

    expect(depth1Nodes.length).toBeGreaterThan(0)

    // Compute distances from focus
    const d1Distances = depth1Nodes.map((n) => distanceTo(n, focusNode.x, focusNode.y))
    const medianD1 = medianOf(d1Distances)

    if (depth2Nodes.length > 0) {
      const d2Distances = depth2Nodes.map((n) => distanceTo(n, focusNode.x, focusNode.y))
      const medianD2 = medianOf(d2Distances)

      // Depth-2 median distance must be greater than depth-1 median
      expect(medianD2).toBeGreaterThan(medianD1)
    }

    // Focus node should be near the center of its depth-1 ring
    // (average of depth-1 positions should be close to focus)
    if (depth1Nodes.length >= 3) {
      const avgD1x = depth1Nodes.reduce((s, n) => s + n.x, 0) / depth1Nodes.length
      const avgD1y = depth1Nodes.reduce((s, n) => s + n.y, 0) / depth1Nodes.length
      const centerOffset = distanceTo({ x: avgD1x, y: avgD1y }, focusNode.x, focusNode.y)

      // The centroid of depth-1 should be close to focus (within 30% of median ring radius)
      expect(centerOffset).toBeLessThan(medianD1 * 0.30)
    }

    // Depth-1 nodes should be reasonably spaced (no heavy overlap)
    if (depth1Nodes.length >= 2) {
      const pairDistances = []
      for (let i = 0; i < depth1Nodes.length; i++) {
        for (let j = i + 1; j < depth1Nodes.length; j++) {
          pairDistances.push(distanceTo(depth1Nodes[i], depth1Nodes[j].x, depth1Nodes[j].y))
        }
      }
      const minPairDist = Math.min(...pairDistances)

      // Minimum distance between any two depth-1 nodes should be > 0
      // (they shouldn't perfectly overlap)
      expect(minPairDist).toBeGreaterThan(0)
    }
  })
})
