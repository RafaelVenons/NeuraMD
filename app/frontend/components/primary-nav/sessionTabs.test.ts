import { describe, it, expect } from "vitest"

import { deriveSessionTabs } from "~/components/primary-nav/sessionTabs"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"

function s(
  id: string,
  overrides: Partial<{ slug: string; title: string; alive: boolean; started_at: string | null }> = {}
) {
  return {
    tentacle_id: id,
    slug: id,
    title: id,
    alive: true,
    started_at: null,
    ...overrides,
  }
}

function snapshot(entries: Record<string, "idle" | "processing" | "needs_input" | "exited">): RuntimeStateSnapshot {
  return Object.fromEntries(Object.entries(entries).map(([k, state]) => [k, { state, at: 1 }]))
}

describe("deriveSessionTabs", () => {
  it("drops dead sessions entirely", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("a", { alive: false }), s("b", { alive: true })],
      runtimeStates: {},
    })
    expect(tabs.map((t) => t.id)).toEqual(["b"])
  })

  it("returns an empty list when every session is dead", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("a", { alive: false })],
      runtimeStates: {},
    })
    expect(tabs).toEqual([])
  })

  it("sorts by needs_input > processing > idle > unknown > exited", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("idle"), s("exited"), s("needs"), s("processing"), s("unknown")],
      runtimeStates: snapshot({
        needs: "needs_input",
        processing: "processing",
        idle: "idle",
        exited: "exited",
      }),
    })
    expect(tabs.map((t) => t.id)).toEqual(["needs", "processing", "idle", "unknown", "exited"])
  })

  it("breaks ties by started_at ascending (oldest first)", () => {
    const tabs = deriveSessionTabs({
      sessions: [
        s("a", { started_at: "2026-04-21T10:00:00Z" }),
        s("b", { started_at: "2026-04-21T09:00:00Z" }),
        s("c", { started_at: null }),
      ],
      runtimeStates: snapshot({ a: "processing", b: "processing", c: "processing" }),
    })
    expect(tabs.map((t) => t.id)).toEqual(["b", "a", "c"])
  })

  it("marks needsAttention when state is needs_input", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("a"), s("b")],
      runtimeStates: snapshot({ a: "needs_input", b: "processing" }),
    })
    expect(tabs.find((t) => t.id === "a")?.needsAttention).toBe(true)
    expect(tabs.find((t) => t.id === "b")?.needsAttention).toBe(false)
  })

  it("truncates labels to the configured length with an ellipsis", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("a", { title: "Um título suficientemente longo para passar do limite" })],
      runtimeStates: {},
      maxLabelLength: 16,
    })
    expect(tabs[0]?.label).toBe("Um título sufic…")
    expect(tabs[0]?.label.length).toBe(16)
  })

  it("leaves short labels alone", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("a", { title: "curto" })],
      runtimeStates: {},
      maxLabelLength: 16,
    })
    expect(tabs[0]?.label).toBe("curto")
  })

  it("falls back to tentacle_id when the title is empty", () => {
    const tabs = deriveSessionTabs({
      sessions: [s("abc-123", { title: "" })],
      runtimeStates: {},
    })
    expect(tabs[0]?.label).toBe("abc-123")
  })
})
