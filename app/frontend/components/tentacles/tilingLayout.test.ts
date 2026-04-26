import { describe, it, expect } from "vitest"

import { selectTilingLayout } from "~/components/tentacles/tilingLayout"
import type { TentacleSession } from "~/components/tentacles/types"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"

function s(
  id: string,
  overrides: Partial<{ alive: boolean; title: string; slug: string }> = {}
): TentacleSession {
  return {
    tentacle_id: id,
    slug: overrides.slug ?? id,
    title: overrides.title ?? id,
    alive: overrides.alive ?? true,
    pid: 1,
    started_at: null,
    command: null,
  }
}

function snapshot(
  entries: Record<string, { state: "idle" | "processing" | "needs_input" | "exited"; at?: number }>
): RuntimeStateSnapshot {
  return Object.fromEntries(
    Object.entries(entries).map(([id, { state, at }]) => [id, { state, at: at ?? 1 }])
  )
}

const DESKTOP = { width: 1920, height: 1080 }
const TABLET = { width: 1024, height: 768 }
const MOBILE = { width: 480, height: 800 }

describe("selectTilingLayout", () => {
  describe("empty", () => {
    it("returns an empty layout when there are no sessions", () => {
      const layout = selectTilingLayout({
        sessions: [],
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toEqual([])
      expect(layout.cards).toEqual([])
      expect(layout.miniGraphSlot).toBeNull()
      expect(layout.hasMore).toBe(false)
    })

    it("ignores dead sessions", () => {
      const layout = selectTilingLayout({
        sessions: [s("a", { alive: false }), s("b", { alive: false })],
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toEqual([])
    })
  })

  describe("desktop ≥ 1280px", () => {
    it("N=1: single fullscreen tile", () => {
      const layout = selectTilingLayout({
        sessions: [s("a")],
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toHaveLength(1)
      const [only] = layout.tiles
      expect(only).toMatchObject({
        kind: "terminal",
        col: 1,
        row: 1,
        colSpan: 1,
        rowSpan: 1,
        weight: 1,
      })
      expect(only?.session.tentacle_id).toBe("a")
      expect(layout.columns).toEqual([1])
      expect(layout.rows).toEqual([1])
    })

    it("N=2: 2 columns × 1 row, even weights", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b")],
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toHaveLength(2)
      expect(layout.columns).toEqual([1, 1])
      expect(layout.rows).toEqual([1])
      expect(layout.tiles.map((t) => t.weight)).toEqual([0.5, 0.5])
      expect(layout.tiles.map((t) => `${t.col},${t.row}`)).toEqual(["1,1", "2,1"])
    })

    it("N=3: golden-ratio left-large + 2 stacked right", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.columns).toEqual([0.62, 0.38])
      expect(layout.rows).toEqual([1, 1])
      const [large, top, bottom] = layout.tiles
      expect(large).toMatchObject({ col: 1, row: 1, colSpan: 1, rowSpan: 2 })
      expect(top).toMatchObject({ col: 2, row: 1, colSpan: 1, rowSpan: 1 })
      expect(bottom).toMatchObject({ col: 2, row: 2, colSpan: 1, rowSpan: 1 })
      expect(large?.weight).toBeCloseTo(0.62, 2)
      expect(top?.weight).toBeCloseTo(0.19, 2)
      expect(bottom?.weight).toBeCloseTo(0.19, 2)
    })

    it("N=4: 2×2 even", () => {
      const ids = ["a", "b", "c", "d"]
      const layout = selectTilingLayout({
        sessions: ids.map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.columns).toEqual([1, 1])
      expect(layout.rows).toEqual([1, 1])
      expect(layout.tiles).toHaveLength(4)
      expect(layout.tiles.every((t) => t.weight === 0.25)).toBe(true)
      expect(layout.tiles.map((t) => `${t.col},${t.row}`)).toEqual(["1,1", "2,1", "1,2", "2,2"])
    })

    it("N=5: 3×2 with one empty corner", () => {
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.columns).toEqual([1, 1, 1])
      expect(layout.rows).toEqual([1, 1])
      expect(layout.tiles).toHaveLength(5)
    })

    it("N=6: 3×2 all filled", () => {
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e", "f"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.columns).toEqual([1, 1, 1])
      expect(layout.rows).toEqual([1, 1])
      expect(layout.tiles).toHaveLength(6)
    })

    it("N=8: 3×3 grid with miniGraph in last slot", () => {
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e", "f", "g", "h"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.columns).toEqual([1, 1, 1])
      expect(layout.rows).toEqual([1, 1, 1])
      expect(layout.tiles).toHaveLength(8)
      expect(layout.miniGraphSlot).toEqual({ col: 3, row: 3, colSpan: 1, rowSpan: 1 })
    })

    it("N=9: 3×3 grid full, miniGraph migrates to drawer (null slot)", () => {
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e", "f", "g", "h", "i"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toHaveLength(9)
      expect(layout.miniGraphSlot).toBeNull()
    })

    it("N=10: wall mode — 2 large terminals + 8 cards", () => {
      const layout = selectTilingLayout({
        sessions: Array.from({ length: 10 }, (_, i) => s(`t${i}`)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles).toHaveLength(2)
      expect(layout.cards).toHaveLength(8)
      expect(layout.miniGraphSlot).toBeNull()
    })

    it("hard cap at 16 sessions, sets hasMore=true", () => {
      const layout = selectTilingLayout({
        sessions: Array.from({ length: 20 }, (_, i) => s(`t${i}`)),
        focusedId: null,
        runtimeStates: {},
        viewport: DESKTOP,
      })
      expect(layout.tiles.length + layout.cards.length).toBe(16)
      expect(layout.hasMore).toBe(true)
    })
  })

  describe("priority for large slots", () => {
    it("N=3: needs_input session takes the large slot", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: null,
        runtimeStates: snapshot({ b: { state: "needs_input", at: 100 } }),
        viewport: DESKTOP,
      })
      const large = layout.tiles.find((t) => t.colSpan === 1 && t.rowSpan === 2)!
      expect(large.session.tentacle_id).toBe("b")
    })

    it("N=3: most-recent needs_input wins ties", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: null,
        runtimeStates: snapshot({
          a: { state: "needs_input", at: 50 },
          c: { state: "needs_input", at: 200 },
        }),
        viewport: DESKTOP,
      })
      const large = layout.tiles.find((t) => t.rowSpan === 2)!
      expect(large.session.tentacle_id).toBe("c")
    })

    it("N=3: falls back to processing when nothing needs input", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: null,
        runtimeStates: snapshot({ b: { state: "processing", at: 100 } }),
        viewport: DESKTOP,
      })
      const large = layout.tiles.find((t) => t.rowSpan === 2)!
      expect(large.session.tentacle_id).toBe("b")
    })

    it("N=3: explicit focusedId wins over plain idle", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: "c",
        runtimeStates: {},
        viewport: DESKTOP,
      })
      const large = layout.tiles.find((t) => t.rowSpan === 2)!
      expect(large.session.tentacle_id).toBe("c")
    })

    it("N=3: focusedId loses to needs_input", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: "a",
        runtimeStates: snapshot({ c: { state: "needs_input", at: 100 } }),
        viewport: DESKTOP,
      })
      const large = layout.tiles.find((t) => t.rowSpan === 2)!
      expect(large.session.tentacle_id).toBe("c")
    })

    it("N=10: top-2 large slots get the highest-priority sessions", () => {
      const sessions = Array.from({ length: 10 }, (_, i) => s(`t${i}`))
      const layout = selectTilingLayout({
        sessions,
        focusedId: null,
        runtimeStates: snapshot({
          t5: { state: "needs_input", at: 200 },
          t8: { state: "needs_input", at: 100 },
        }),
        viewport: DESKTOP,
      })
      expect(layout.tiles).toHaveLength(2)
      expect(layout.tiles.map((t) => t.session.tentacle_id)).toEqual(["t5", "t8"])
    })
  })

  describe("tablet 768–1279px", () => {
    it("caps to 2 columns even when N=3 would request more", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c")],
        focusedId: null,
        runtimeStates: {},
        viewport: TABLET,
      })
      expect(layout.columns.length).toBeLessThanOrEqual(2)
    })

    it("caps to 2 columns at N=6 (becomes 2x3 instead of 3x2)", () => {
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e", "f"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: TABLET,
      })
      expect(layout.columns.length).toBeLessThanOrEqual(2)
    })
  })

  describe("mobile < 768px", () => {
    it("renders all alive sessions in a 1-column carousel, no miniGraph", () => {
      const layout = selectTilingLayout({
        sessions: [s("a"), s("b"), s("c"), s("d"), s("e")],
        focusedId: null,
        runtimeStates: {},
        viewport: MOBILE,
      })
      expect(layout.columns).toEqual([1])
      expect(layout.tiles).toHaveLength(5)
      expect(layout.tiles.every((t) => t.colSpan === 1 && t.col === 1)).toBe(true)
      expect(layout.miniGraphSlot).toBeNull()
      expect(layout.cards).toEqual([])
    })
  })

  describe("cramped degradation", () => {
    it("converts terminals to cards when tile dimensions < min legible (520×220)", () => {
      // 9 sessions on a 1280×400 viewport: each tile is ~426×133 — below 220 min height
      const layout = selectTilingLayout({
        sessions: ["a", "b", "c", "d", "e", "f", "g", "h", "i"].map((id) => s(id)),
        focusedId: null,
        runtimeStates: {},
        viewport: { width: 1280, height: 400 },
      })
      expect(layout.tiles.length).toBeLessThan(9)
      expect(layout.cards.length).toBeGreaterThan(0)
    })
  })
})
