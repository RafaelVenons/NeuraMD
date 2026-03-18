import { DirectedGraph } from "graphology"
import { edgePaddingForRole, resolveArrowDirectionHint, resolveSigmaEdgeType } from "graph/graph_custom_edge_program"

export function buildGraph(dataset) {
  const graph = new DirectedGraph()
  const seenPairs = new Set()
  const dropped = []

  for (const note of dataset.notes || []) {
    const degree = Number(note.incoming_link_count || 0) + Number(note.outgoing_link_count || 0)
    const baseSize = resolveNodeBaseSize(degree)

    graph.addNode(note.id, {
      id: note.id,
      slug: note.slug,
      label: note.title || note.slug,
      title: note.title || note.slug,
      excerpt: note.excerpt || null,
      updatedAt: note.updated_at || null,
      createdAt: note.created_at || null,
      incomingLinkCount: note.incoming_link_count || 0,
      outgoingLinkCount: note.outgoing_link_count || 0,
      degree,
      baseSize,
      hasLinks: note.has_links === true,
      promiseTitles: note.promise_titles || [],
      promiseCount: note.promise_count || 0,
      hasPromises: note.has_promises === true,
      noteTags: [],
      x: 0,
      y: 0,
      size: baseSize,
      color: "#93c5fd",
      baseColor: "#93c5fd",
      borderColor: "#dbeafe",
      baseBorderColor: "#dbeafe",
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
    const size = edgeSizeForRole(link.hier_role)
    const color = edgeColorForRole(link.hier_role)
    graph.addDirectedEdgeWithKey(link.id, link.src_note_id, link.dst_note_id, {
      id: link.id,
      hierRole: link.hier_role,
      context: link.context || null,
      createdAt: link.created_at || null,
      linkTags: [],
      label: "",
      size,
      color,
      baseColor: color,
      hidden: false,
      forceLabel: false,
      type: resolveSigmaEdgeType(link.hier_role),
      visualArrowSide: resolveArrowDirectionHint(link.hier_role),
      srcPadding: edgeSourcePaddingForRole(link.hier_role, size),
      dstPadding: edgeTargetPaddingForRole(link.hier_role, size)
    })
  }

  return { graph, dropped }
}

function edgeSizeForRole(hierRole) {
  if (hierRole === "target_is_parent") return 4.4
  if (hierRole === "target_is_child") return 2.8
  if (hierRole === "same_level") return 3.2
  return 1.7
}

function edgeColorForRole(hierRole) {
  if (hierRole === "target_is_parent") return "#f97316"
  if (hierRole === "target_is_child") return "#38bdf8"
  if (hierRole === "same_level") return "#a3e635"
  return "#64748b"
}

function edgeSourcePaddingForRole(hierRole, edgeSize) {
  return edgePaddingForRole(hierRole, edgeSize, "source")
}

function edgeTargetPaddingForRole(hierRole, edgeSize) {
  return edgePaddingForRole(hierRole, edgeSize, "target")
}

function resolveNodeBaseSize(degree) {
  return Math.max(7.2, Math.min(16.5, 7.2 + (Math.sqrt(Math.max(0, degree)) * 2.4)))
}
