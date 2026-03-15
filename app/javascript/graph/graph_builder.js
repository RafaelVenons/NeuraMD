import { DirectedGraph } from "graphology"
import { resolveArrowDirectionHint, resolveSigmaEdgeType } from "graph/graph_custom_edge_program"

export function buildGraph(dataset) {
  const graph = new DirectedGraph()
  const seenPairs = new Set()
  const dropped = []

  for (const note of dataset.notes || []) {
    graph.addNode(note.id, {
      id: note.id,
      slug: note.slug,
      label: note.title || note.slug,
      title: note.title || note.slug,
      excerpt: note.excerpt || null,
      updatedAt: note.updated_at || null,
      createdAt: note.created_at || null,
      noteTags: [],
      x: 0,
      y: 0,
      size: 6,
      color: "#7dd3fc",
      baseColor: "#7dd3fc",
      labelColor: "#f8fafc",
      hidden: false,
      highlighted: false,
      forceLabel: false,
      type: "circle"
    })
  }

  for (const link of dataset.links || []) {
    if (!graph.hasNode(link.src_note_id) || !graph.hasNode(link.dst_note_id)) {
      dropped.push({ id: link.id, reason: "missing-node" })
      continue
    }

    const pairKey = `${link.src_note_id}->${link.dst_note_id}`
    if (seenPairs.has(pairKey)) {
      dropped.push({ id: link.id, reason: "duplicate-pair" })
      continue
    }

    seenPairs.add(pairKey)
    graph.addDirectedEdgeWithKey(link.id, link.src_note_id, link.dst_note_id, {
      id: link.id,
      hierRole: link.hier_role,
      context: link.context || null,
      createdAt: link.created_at || null,
      linkTags: [],
      label: "",
      size: 1.8,
      color: "#64748b",
      baseColor: "#64748b",
      hidden: false,
      forceLabel: false,
      type: resolveSigmaEdgeType(link.hier_role),
      visualArrowSide: resolveArrowDirectionHint(link.hier_role),
      srcPadding: 4,
      dstPadding: 10
    })
  }

  return { graph, dropped }
}
