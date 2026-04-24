import { describe, it, expect } from "vitest"

import { agentColorMap, DEFAULT_AGENT_COLOR } from "~/components/graph/agentPalette"
import type { GraphTag } from "~/components/graph/types"

describe("agentColorMap", () => {
  const tags: GraphTag[] = [
    { id: "team", name: "agente-team" },
    { id: "rubi", name: "agente-rubi" },
    { id: "react", name: "agente-react" },
    { id: "uxui", name: "agente-uxui" },
    { id: "unknown", name: "agente-misterio" },
    { id: "other", name: "shop" },
  ]

  it("returns an empty map when no agents are given", () => {
    expect(agentColorMap(new Set(), tags, [])).toEqual(new Map())
  })

  it("maps each agent to the palette color of its role tag", () => {
    const noteTags = [
      { note_id: "a", tag_id: "team" },
      { note_id: "a", tag_id: "rubi" },
      { note_id: "b", tag_id: "team" },
      { note_id: "b", tag_id: "react" },
    ]
    const result = agentColorMap(new Set(["a", "b"]), tags, noteTags)
    expect(result.get("a")).toBe("#ef4444")
    expect(result.get("b")).toBe("#38bdf8")
  })

  it("ignores the agente-team umbrella tag when picking a role", () => {
    const noteTags = [
      { note_id: "a", tag_id: "team" },
      { note_id: "a", tag_id: "uxui" },
    ]
    const result = agentColorMap(new Set(["a"]), tags, noteTags)
    expect(result.get("a")).toBe("#c084fc")
  })

  it("falls back to the default color when no known role tag is found", () => {
    const noteTags = [
      { note_id: "a", tag_id: "team" },
      { note_id: "a", tag_id: "unknown" },
      { note_id: "b", tag_id: "team" },
    ]
    const result = agentColorMap(new Set(["a", "b"]), tags, noteTags)
    expect(result.get("a")).toBe(DEFAULT_AGENT_COLOR)
    expect(result.get("b")).toBe(DEFAULT_AGENT_COLOR)
  })

  it("ignores non-agent tags when deriving a role", () => {
    const noteTags = [
      { note_id: "a", tag_id: "team" },
      { note_id: "a", tag_id: "other" },
    ]
    const result = agentColorMap(new Set(["a"]), tags, noteTags)
    expect(result.get("a")).toBe(DEFAULT_AGENT_COLOR)
  })
})
