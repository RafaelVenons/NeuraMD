import { describe, it, expect } from "vitest"

import {
  FIT_PADDING,
  MAX_SCALE,
  MIN_SCALE,
  ZOOM_FACTOR,
  applyPan,
  applyZoomAroundPoint,
  clampScale,
  computeFitTransform,
  screenToGraph,
} from "~/components/graph/canvasTransform"

const identity = { translateX: 0, translateY: 0, scale: 1 }

describe("clampScale", () => {
  it("keeps values inside bounds", () => {
    expect(clampScale(1)).toBe(1)
    expect(clampScale(2.5)).toBe(2.5)
  })

  it("clamps to MIN_SCALE", () => {
    expect(clampScale(MIN_SCALE / 2)).toBe(MIN_SCALE)
    expect(clampScale(0)).toBe(MIN_SCALE)
  })

  it("clamps to MAX_SCALE", () => {
    expect(clampScale(MAX_SCALE * 2)).toBe(MAX_SCALE)
    expect(clampScale(Infinity)).toBe(MAX_SCALE)
  })
})

describe("applyZoomAroundPoint", () => {
  it("zooms in by ZOOM_FACTOR without moving the pivot point", () => {
    const cx = 400
    const cy = 300
    const next = applyZoomAroundPoint(identity, cx, cy, 1)
    expect(next.scale).toBeCloseTo(1 + ZOOM_FACTOR)

    const before = {
      x: (cx - identity.translateX) / identity.scale,
      y: (cy - identity.translateY) / identity.scale,
    }
    const after = {
      x: (cx - next.translateX) / next.scale,
      y: (cy - next.translateY) / next.scale,
    }
    expect(after.x).toBeCloseTo(before.x)
    expect(after.y).toBeCloseTo(before.y)
  })

  it("zooms out by ZOOM_FACTOR", () => {
    const next = applyZoomAroundPoint(identity, 100, 100, -1)
    expect(next.scale).toBeCloseTo(1 - ZOOM_FACTOR)
  })

  it("clamps scale at MAX_SCALE", () => {
    const prev = { ...identity, scale: MAX_SCALE }
    const next = applyZoomAroundPoint(prev, 0, 0, 1)
    expect(next.scale).toBe(MAX_SCALE)
  })

  it("clamps scale at MIN_SCALE", () => {
    const prev = { ...identity, scale: MIN_SCALE }
    const next = applyZoomAroundPoint(prev, 0, 0, -1)
    expect(next.scale).toBe(MIN_SCALE)
  })
})

describe("screenToGraph", () => {
  it("returns the graph coordinate under identity transform", () => {
    const rect = { width: 800, height: 600 }
    expect(screenToGraph(120, 90, rect, identity)).toEqual({ x: 120, y: 90 })
  })

  it("subtracts viewport left/top offsets", () => {
    const rect = { width: 800, height: 600, left: 20, top: 15 }
    expect(screenToGraph(120, 90, rect, identity)).toEqual({ x: 100, y: 75 })
  })

  it("inverts scale and translate", () => {
    const transform = { translateX: 50, translateY: 30, scale: 2 }
    const rect = { width: 800, height: 600 }
    expect(screenToGraph(250, 130, rect, transform)).toEqual({ x: 100, y: 50 })
  })
})

describe("computeFitTransform", () => {
  it("returns null for empty nodes", () => {
    expect(computeFitTransform([], { width: 800, height: 600 })).toBeNull()
  })

  it("returns null when viewport has zero size", () => {
    const nodes = [{ x: 0, y: 0 }]
    expect(computeFitTransform(nodes, { width: 0, height: 600 })).toBeNull()
    expect(computeFitTransform(nodes, { width: 800, height: 0 })).toBeNull()
  })

  it("centers a single node in the viewport", () => {
    const rect = { width: 800, height: 600 }
    const transform = computeFitTransform([{ x: 0, y: 0 }], rect)!
    expect(transform).not.toBeNull()

    const projectedX = transform.translateX + 0 * transform.scale
    const projectedY = transform.translateY + 0 * transform.scale
    expect(projectedX).toBeCloseTo(rect.width / 2)
    expect(projectedY).toBeCloseTo(rect.height / 2)
  })

  it("fits multiple nodes within padding", () => {
    const rect = { width: 800, height: 600 }
    const nodes = [
      { x: -100, y: -100 },
      { x: 100, y: 100 },
    ]
    const t = computeFitTransform(nodes, rect)!
    expect(t).not.toBeNull()

    for (const n of nodes) {
      const px = t.translateX + n.x * t.scale
      const py = t.translateY + n.y * t.scale
      expect(px).toBeGreaterThanOrEqual(FIT_PADDING - 0.001)
      expect(px).toBeLessThanOrEqual(rect.width - FIT_PADDING + 0.001)
      expect(py).toBeGreaterThanOrEqual(FIT_PADDING - 0.001)
      expect(py).toBeLessThanOrEqual(rect.height - FIT_PADDING + 0.001)
    }
  })

  it("clamps fit scale to MAX_SCALE when bounds are tiny", () => {
    const rect = { width: 800, height: 600 }
    const nodes = [
      { x: 0, y: 0 },
      { x: 1, y: 1 },
    ]
    const t = computeFitTransform(nodes, rect)!
    expect(t.scale).toBe(MAX_SCALE)
  })

  it("clamps fit scale to MIN_SCALE when bounds are huge", () => {
    const rect = { width: 800, height: 600 }
    const nodes = [
      { x: -1_000_000, y: -1_000_000 },
      { x: 1_000_000, y: 1_000_000 },
    ]
    const t = computeFitTransform(nodes, rect)!
    expect(t.scale).toBe(MIN_SCALE)
  })
})

describe("applyPan", () => {
  it("adds the pointer delta to the starting translate", () => {
    const result = applyPan(identity, 10, 20, 100, 200, 130, 180)
    expect(result.translateX).toBe(40)
    expect(result.translateY).toBe(0)
    expect(result.scale).toBe(identity.scale)
  })

  it("returns zero delta when pointer has not moved", () => {
    const prev = { translateX: 5, translateY: 7, scale: 1.5 }
    const result = applyPan(prev, 5, 7, 100, 100, 100, 100)
    expect(result.translateX).toBe(5)
    expect(result.translateY).toBe(7)
    expect(result.scale).toBe(1.5)
  })
})
