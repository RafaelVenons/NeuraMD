import { describe, it, expect } from "vitest"

import { selectDashboardLayout } from "~/components/tentacles/dashboardLayout"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"

function s(id: string, overrides: Partial<{ title: string; alive: boolean }> = {}) {
  return {
    tentacle_id: id,
    slug: id,
    title: id,
    alive: true,
    pid: 1,
    started_at: null,
    command: null,
    ...overrides,
  }
}

function snapshot(entries: Record<string, "idle" | "processing" | "needs_input" | "exited">): RuntimeStateSnapshot {
  const now = 1
  return Object.fromEntries(Object.entries(entries).map(([k, state]) => [k, { state, at: now }]))
}

describe("selectDashboardLayout", () => {
  it("returns a null layout when there are no sessions", () => {
    const layout = selectDashboardLayout({ sessions: [], focusedId: null, runtimeStates: {} })
    expect(layout).toEqual({ focused: null, rest: [], needsAttention: [] })
  })

  it("uses the provided focusedId when it matches a session", () => {
    const [a, b, c] = [s("a"), s("b"), s("c")]
    const layout = selectDashboardLayout({
      sessions: [a, b, c],
      focusedId: "b",
      runtimeStates: {},
    })
    expect(layout.focused).toBe(b)
    expect(layout.rest.map((x) => x.tentacle_id)).toEqual(["a", "c"])
  })

  it("falls back to the first needs_input session when focusedId is missing", () => {
    const [a, b, c] = [s("a"), s("b"), s("c")]
    const layout = selectDashboardLayout({
      sessions: [a, b, c],
      focusedId: null,
      runtimeStates: snapshot({ b: "needs_input" }),
    })
    expect(layout.focused).toBe(b)
    expect(layout.rest.map((x) => x.tentacle_id)).toEqual(["a", "c"])
  })

  it("falls back to the first session when nothing needs attention", () => {
    const [a, b] = [s("a"), s("b")]
    const layout = selectDashboardLayout({
      sessions: [a, b],
      focusedId: null,
      runtimeStates: snapshot({ a: "processing", b: "idle" }),
    })
    expect(layout.focused).toBe(a)
  })

  it("ignores an invalid focusedId and falls back", () => {
    const [a, b] = [s("a"), s("b")]
    const layout = selectDashboardLayout({
      sessions: [a, b],
      focusedId: "unknown",
      runtimeStates: snapshot({ b: "needs_input" }),
    })
    expect(layout.focused).toBe(b)
  })

  it("collects every session with needs_input into needsAttention", () => {
    const [a, b, c] = [s("a"), s("b"), s("c")]
    const layout = selectDashboardLayout({
      sessions: [a, b, c],
      focusedId: "a",
      runtimeStates: snapshot({ b: "needs_input", c: "needs_input" }),
    })
    expect(layout.needsAttention.map((x) => x.tentacle_id)).toEqual(["b", "c"])
  })

  it("sorts rest by priority: needs_input, processing, idle, exited, unknown", () => {
    const list = [s("idle"), s("exited"), s("needs"), s("processing"), s("unknown")]
    const layout = selectDashboardLayout({
      sessions: list,
      focusedId: null,
      runtimeStates: snapshot({
        needs: "needs_input",
        processing: "processing",
        idle: "idle",
        exited: "exited",
      }),
    })
    expect(layout.focused?.tentacle_id).toBe("needs")
    expect(layout.rest.map((x) => x.tentacle_id)).toEqual(["processing", "idle", "unknown", "exited"])
  })
})
