import { resolveNodeDepth } from "graph/graph_focus"
import { resolvePriorityTag } from "graph/graph_tags"
import { borderColorForNode, colorForEdge, colorForNode, labelColorForNode, roleLabel } from "graph/graph_style"

export function computeDisplayState(state) {
  const nodeDisplay = new Map()
  const edgeDisplay = new Map()
  const visibleIncidentNodeIds = new Set()
  const selectedTagIds = new Set((state.ui.selectedTagIds || []).map(String))
  const tagFilterActive = state.ui.filterMode === "focused-tags" && selectedTagIds.size > 0
  const tagFilteredNodeIds = new Set()
  const tagFilteredEdgeIds = new Set()
  const ghostNodeIds = new Set()
  const ghostEdgeIds = new Set()

  state.graph.forEachNode((nodeId, attributes) => {
    const haystack = `${attributes.label} ${attributes.excerpt || ""}`.toLowerCase()
    const priorityTagId = resolvePriorityTag(attributes.noteTags, state.ui.activeTagsOrdered, state.ui.topN)
    const matchesSearch = !state.ui.searchQuery || haystack.includes(state.ui.searchQuery)
    const depthFromFocus = resolveNodeDepth(nodeId, state.ui.focusedNodeId, state.indexes, state.ui.focusDepth)
    const matchesSelectedTags = intersectsSelectedTags(attributes.noteTags, selectedTagIds)

    if (tagFilterActive && matchesSelectedTags) tagFilteredNodeIds.add(nodeId)

    nodeDisplay.set(nodeId, {
      matchesSearch,
      priorityTagId,
      depthFromFocus,
      matchesSelectedTags
    })
  })

  state.graph.forEachEdge((edgeId, attributes, source, target) => {
    if (tagFilterActive && intersectsSelectedTags(attributes.linkTags, selectedTagIds)) {
      tagFilteredEdgeIds.add(edgeId)
      tagFilteredNodeIds.add(source)
      tagFilteredNodeIds.add(target)
    }
  })

  if (tagFilterActive) {
    state.graph.forEachEdge((edgeId, _attributes, source, target) => {
      if (tagFilteredEdgeIds.has(edgeId)) return
      if (!tagFilteredNodeIds.has(source) && !tagFilteredNodeIds.has(target)) return

      ghostEdgeIds.add(edgeId)
      if (!tagFilteredNodeIds.has(source)) ghostNodeIds.add(source)
      if (!tagFilteredNodeIds.has(target)) ghostNodeIds.add(target)
    })
  }

  state.graph.forEachEdge((edgeId, attributes, source, target) => {
    const roleKey = attributes.hierRole || "null"
    if (!state.ui.enabledRoles.has(roleKey)) {
      edgeDisplay.set(edgeId, { hidden: true })
      return
    }

    const sourceNode = nodeDisplay.get(source)
    const targetNode = nodeDisplay.get(target)
    const priorityTagId = resolvePriorityTag(attributes.linkTags, state.ui.activeTagsOrdered, state.ui.topN)
    const relevantToTags = Boolean(priorityTagId || sourceNode.priorityTagId || targetNode.priorityTagId)
    const withinFocus = state.ui.focusedNodeId === null ||
      (sourceNode.depthFromFocus <= state.ui.focusDepth && targetNode.depthFromFocus <= state.ui.focusDepth)
    const incidentToFocus = source === state.ui.focusedNodeId || target === state.ui.focusedNodeId
    const visibleBySearch = sourceNode.matchesSearch || targetNode.matchesSearch
    const selectedByTagFilter = tagFilteredEdgeIds.has(edgeId)
    const ghostedByTagFilter = ghostEdgeIds.has(edgeId)

    const hidden = !visibleBySearch || (
      tagFilterActive
        ? (!selectedByTagFilter && !ghostedByTagFilter)
        : (
          state.ui.filterMode === "focused-tags" &&
          state.ui.activeTagsOrdered.length > 0 &&
          !relevantToTags
        )
    )

    if (!hidden) {
      visibleIncidentNodeIds.add(source)
      visibleIncidentNodeIds.add(target)
    }

    edgeDisplay.set(edgeId, {
      hidden,
      priorityTagId,
      color: colorForEdge(
        priorityTagId,
        attributes.hierRole,
        state.indexes.tagMetaById,
        incidentToFocus || sourceNode.depthFromFocus === 1 || targetNode.depthFromFocus === 1,
        sourceNode.depthFromFocus === 2 || targetNode.depthFromFocus === 2,
        ghostedByTagFilter || state.ui.focusedNodeId !== null && (!withinFocus || !incidentToFocus && sourceNode.depthFromFocus >= 1 && targetNode.depthFromFocus >= 1)
      ),
      size: resolveEdgeDisplaySize(
        attributes.hierRole,
        incidentToFocus,
        withinFocus,
        sourceNode.depthFromFocus,
        targetNode.depthFromFocus,
        state.ui.focusedNodeId !== null,
        ghostedByTagFilter
      ),
      type: attributes.type,
      label: roleLabel(attributes.hierRole),
      ghostedByTagFilter
    })
  })

  state.graph.forEachNode((nodeId, attributes) => {
    const base = nodeDisplay.get(nodeId)
    const isFocused = nodeId === state.ui.focusedNodeId
    const isHovered = nodeId === state.ui.hoveredNodeId
    const hasVisibleIncidentEdge = visibleIncidentNodeIds.has(nodeId)

    let filterState = "normal"
    if (state.ui.focusedNodeId !== null && base.depthFromFocus > state.ui.focusDepth && nodeId !== state.ui.focusedNodeId) {
      filterState = "ghost"
    }

    if (tagFilterActive) {
      if (tagFilteredNodeIds.has(nodeId)) filterState = "normal"
      else if (ghostNodeIds.has(nodeId) || hasVisibleIncidentEdge) filterState = "ghost"
      else filterState = "hidden"
    } else if (state.ui.filterMode === "focused-tags" && state.ui.activeTagsOrdered.length > 0 && !base.priorityTagId) {
      filterState = hasVisibleIncidentEdge ? "ghost" : "hidden"
    }

    const hidden = !base.matchesSearch || filterState === "hidden"
    const size = resolveNodeDisplaySize(attributes.baseSize, isFocused, base.depthFromFocus, filterState)

    nodeDisplay.set(nodeId, {
      ...base,
      filterState,
      hidden,
      size,
      color: colorForNode(base.priorityTagId, filterState, state.indexes.tagMetaById, isFocused, isHovered),
      borderColor: borderColorForNode(base.priorityTagId, filterState, state.indexes.tagMetaById, isFocused, isHovered),
      labelColor: labelColorForNode(filterState, isFocused, isHovered),
      forceLabel: !hidden && filterState !== "ghost"
    })
  })

  return { nodes: nodeDisplay, edges: edgeDisplay }
}

function resolveEdgeDisplaySize(hierRole, incidentToFocus, withinFocus, sourceDepth, targetDepth, hasFocus, ghostedByTagFilter = false) {
  const baseSize =
    hierRole === "target_is_parent" ? 3.4 :
      hierRole === "target_is_child" ? 2.2 :
        hierRole === "same_level" ? 2.5 :
          1.7

  if (ghostedByTagFilter) return Math.max(0.95, baseSize - 0.9)
  if (incidentToFocus) return baseSize + 1.1
  if (hasFocus && !withinFocus) return Math.max(1.05, baseSize - 0.6)
  if (sourceDepth <= 1 || targetDepth <= 1) return baseSize + 0.45
  return baseSize
}

function resolveNodeDisplaySize(baseSize, isFocused, depthFromFocus, filterState) {
  const nodeBaseSize = Number(baseSize) || 7.8

  if (isFocused) return nodeBaseSize + 5
  if (depthFromFocus === 1) return nodeBaseSize + 1.6
  if (depthFromFocus === 2) return nodeBaseSize + 0.7
  if (filterState === "ghost") return Math.max(5.8, nodeBaseSize - 2.2)
  return nodeBaseSize
}

function intersectsSelectedTags(tagIds, selectedTagIds) {
  if (!selectedTagIds.size) return false
  return (tagIds || []).some((tagId) => selectedTagIds.has(String(tagId)))
}
