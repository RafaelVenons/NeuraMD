import { bfsFromNode } from "graphology-traversal"

export function buildIndexes(dataset, graph) {
  const tagsByNoteId = new Map()
  const tagsByLinkId = new Map()
  const tagMetaById = new Map()
  const outEdgesByNodeId = new Map()
  const inEdgesByNodeId = new Map()

  graph.forEachNode((nodeId) => {
    tagsByNoteId.set(nodeId, [])
    outEdgesByNodeId.set(nodeId, [])
    inEdgesByNodeId.set(nodeId, [])
  })

  graph.forEachEdge((edgeId, attributes, source, target) => {
    tagsByLinkId.set(edgeId, [])
    outEdgesByNodeId.get(source)?.push(edgeId)
    inEdgesByNodeId.get(target)?.push(edgeId)
  })

  for (const tag of dataset.tags || []) tagMetaById.set(tag.id, tag)
  for (const row of dataset.noteTags || []) tagsByNoteId.get(row.note_id)?.push(row.tag_id)
  for (const row of dataset.linkTags || []) tagsByLinkId.get(row.note_link_id)?.push(row.tag_id)

  graph.forEachNode((nodeId) => {
    graph.setNodeAttribute(nodeId, "noteTags", tagsByNoteId.get(nodeId) || [])
  })

  graph.forEachEdge((edgeId) => {
    graph.setEdgeAttribute(edgeId, "linkTags", tagsByLinkId.get(edgeId) || [])
  })

  const neighborDepth1Cache = new Map()
  const neighborDepth2Cache = new Map()

  graph.forEachNode((nodeId) => {
    neighborDepth1Cache.set(nodeId, collectDepth(graph, nodeId, 1))
    neighborDepth2Cache.set(nodeId, collectDepth(graph, nodeId, 2))
  })

  return {
    tagsByNoteId,
    tagsByLinkId,
    tagMetaById,
    outEdgesByNodeId,
    inEdgesByNodeId,
    neighborDepth1Cache,
    neighborDepth2Cache
  }
}

function collectDepth(graph, rootId, maxDepth) {
  const visited = new Set()

  bfsFromNode(graph, rootId, (nodeId, _attributes, depth) => {
    if (depth === 0 || depth > maxDepth) return
    visited.add(nodeId)
  }, { mode: "outbound" })

  bfsFromNode(graph, rootId, (nodeId, _attributes, depth) => {
    if (depth === 0 || depth > maxDepth) return
    visited.add(nodeId)
  }, { mode: "inbound" })

  return visited
}
