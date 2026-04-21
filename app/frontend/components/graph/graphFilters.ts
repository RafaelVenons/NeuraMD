import type { GraphEdge, GraphNode, NodeType } from "~/components/graph/types"

export type TypeCounts = { root: number; structure: number; leaf: number; tentacle: number }

export function countByType(nodes: { type: NodeType }[]): TypeCounts {
  return nodes.reduce(
    (acc, node) => {
      acc[node.type] += 1
      return acc
    },
    { root: 0, structure: 0, leaf: 0, tentacle: 0 } as TypeCounts
  )
}

export function filterGraph(
  nodes: GraphNode[],
  edges: GraphEdge[],
  noteTags: { note_id: string; tag_id: string }[],
  selected: Set<string>
): { nodes: GraphNode[]; edges: GraphEdge[] } {
  if (selected.size === 0) return { nodes, edges }

  const noteTagIndex = new Map<string, Set<string>>()
  for (const nt of noteTags) {
    let set = noteTagIndex.get(nt.note_id)
    if (!set) {
      set = new Set()
      noteTagIndex.set(nt.note_id, set)
    }
    set.add(nt.tag_id)
  }

  const includedIds = new Set<string>()
  const filteredNodes = nodes.filter((node) => {
    const tags = noteTagIndex.get(node.id)
    if (!tags) return false
    for (const tagId of selected) if (tags.has(tagId)) {
      includedIds.add(node.id)
      return true
    }
    return false
  })

  const filteredEdges = edges.filter((e) => includedIds.has(e.source) && includedIds.has(e.target))
  return { nodes: filteredNodes, edges: filteredEdges }
}

export function tagUsageCounts(
  noteTags: { note_id: string; tag_id: string }[],
  visibleNoteIds: Set<string>
): Map<string, number> {
  const counts = new Map<string, number>()
  for (const nt of noteTags) {
    if (!visibleNoteIds.has(nt.note_id)) continue
    counts.set(nt.tag_id, (counts.get(nt.tag_id) ?? 0) + 1)
  }
  return counts
}
