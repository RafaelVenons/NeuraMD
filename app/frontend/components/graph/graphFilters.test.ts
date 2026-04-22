import { describe, it, expect } from "vitest"

import { agentNoteIds, countByType, filterGraph, tagUsageCounts } from "~/components/graph/graphFilters"
import type { GraphEdge, GraphNode, GraphTag } from "~/components/graph/types"

function node(id: string, type: GraphNode["type"] = "leaf"): GraphNode {
  return {
    id,
    label: id,
    type,
    x: 0,
    y: 0,
    note: {
      id,
      slug: id,
      title: id,
      node_type: type,
      incoming_link_count: 0,
      outgoing_link_count: 0,
      has_links: false,
      promise_count: 0,
      promise_titles: [],
      has_promises: false,
    },
  }
}

function edge(source: string, target: string): GraphEdge {
  return { id: `${source}->${target}`, source, target }
}

describe("countByType", () => {
  it("returns zeros for every type on an empty list", () => {
    expect(countByType([])).toEqual({ root: 0, structure: 0, leaf: 0, tentacle: 0 })
  })

  it("tallies each node by its type", () => {
    const counts = countByType([
      { type: "root" },
      { type: "structure" },
      { type: "structure" },
      { type: "leaf" },
      { type: "tentacle" },
    ])
    expect(counts).toEqual({ root: 1, structure: 2, leaf: 1, tentacle: 1 })
  })
})

describe("filterGraph", () => {
  const nodes = [node("a"), node("b"), node("c"), node("d")]
  const edges = [edge("a", "b"), edge("b", "c"), edge("c", "d"), edge("a", "d")]
  const noteTags = [
    { note_id: "a", tag_id: "t1" },
    { note_id: "b", tag_id: "t1" },
    { note_id: "b", tag_id: "t2" },
    { note_id: "c", tag_id: "t2" },
    { note_id: "d", tag_id: "t3" },
  ]

  it("returns nodes and edges unchanged when no tag is selected", () => {
    const result = filterGraph(nodes, edges, noteTags, new Set())
    expect(result.nodes).toBe(nodes)
    expect(result.edges).toBe(edges)
  })

  it("keeps only nodes that carry the selected tag", () => {
    const result = filterGraph(nodes, edges, noteTags, new Set(["t1"]))
    expect(result.nodes.map((n) => n.id).sort()).toEqual(["a", "b"])
  })

  it("prunes edges where either endpoint is filtered out", () => {
    const result = filterGraph(nodes, edges, noteTags, new Set(["t1"]))
    expect(result.edges).toEqual([edge("a", "b")])
  })

  it("OR-combines multiple selected tags", () => {
    const result = filterGraph(nodes, edges, noteTags, new Set(["t1", "t3"]))
    expect(result.nodes.map((n) => n.id).sort()).toEqual(["a", "b", "d"])
    expect(result.edges.map((e) => e.id).sort()).toEqual(["a->b", "a->d"])
  })

  it("excludes nodes with no tags at all when any filter is active", () => {
    const untagged = node("orphan")
    const result = filterGraph([...nodes, untagged], edges, noteTags, new Set(["t1"]))
    expect(result.nodes.find((n) => n.id === "orphan")).toBeUndefined()
  })

  it("returns empty nodes and edges when no node matches the selected tag", () => {
    const result = filterGraph(nodes, edges, noteTags, new Set(["unknown"]))
    expect(result.nodes).toEqual([])
    expect(result.edges).toEqual([])
  })
})

describe("agentNoteIds", () => {
  const tags: GraphTag[] = [
    { id: "team", name: "agente-team" },
    { id: "gerente", name: "agente-gerente" },
    { id: "other", name: "shop" },
  ]
  const noteTags = [
    { note_id: "a", tag_id: "team" },
    { note_id: "a", tag_id: "gerente" },
    { note_id: "b", tag_id: "team" },
    { note_id: "c", tag_id: "other" },
  ]

  it("returns note ids that carry the agent tag by name", () => {
    const result = agentNoteIds(tags, noteTags, "agente-team")
    expect(result).toEqual(new Set(["a", "b"]))
  })

  it("returns an empty set when the agent tag does not exist", () => {
    const result = agentNoteIds(tags, noteTags, "agente-inexistente")
    expect(result).toEqual(new Set())
  })

  it("returns an empty set when no note carries the tag", () => {
    const result = agentNoteIds(tags, [], "agente-team")
    expect(result).toEqual(new Set())
  })

  it("defaults to the agente-team tag name", () => {
    expect(agentNoteIds(tags, noteTags)).toEqual(new Set(["a", "b"]))
  })
})

describe("tagUsageCounts", () => {
  const noteTags = [
    { note_id: "a", tag_id: "t1" },
    { note_id: "b", tag_id: "t1" },
    { note_id: "b", tag_id: "t2" },
    { note_id: "c", tag_id: "t2" },
  ]

  it("counts tag usage restricted to visible note ids", () => {
    const counts = tagUsageCounts(noteTags, new Set(["a", "b"]))
    expect(counts.get("t1")).toBe(2)
    expect(counts.get("t2")).toBe(1)
  })

  it("ignores note_tag rows whose note is not visible", () => {
    const counts = tagUsageCounts(noteTags, new Set(["a"]))
    expect(counts.get("t1")).toBe(1)
    expect(counts.has("t2")).toBe(false)
  })

  it("returns an empty map when no notes are visible", () => {
    const counts = tagUsageCounts(noteTags, new Set())
    expect(counts.size).toBe(0)
  })
})
