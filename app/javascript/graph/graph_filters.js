import { resolveNodeDepth } from "graph/graph_focus"
import { resolvePriorityTag } from "graph/graph_tags"
import { colorForEdge, colorForNode, labelColorForNode, roleLabel } from "graph/graph_style"

export function computeDisplayState(state) {
  const nodeDisplay = new Map()
  const edgeDisplay = new Map()
  const visibleIncidentNodeIds = new Set()

  state.graph.forEachNode((nodeId, attributes) => {
    const haystack = `${attributes.label} ${attributes.excerpt || ""}`.toLowerCase()
    const priorityTagId = resolvePriorityTag(attributes.noteTags, state.ui.activeTagsOrdered, state.ui.topN)
    const matchesSearch = !state.ui.searchQuery || haystack.includes(state.ui.searchQuery)
    const depthFromFocus = resolveNodeDepth(nodeId, state.ui.focusedNodeId, state.indexes, state.ui.focusDepth)

    nodeDisplay.set(nodeId, {
      matchesSearch,
      priorityTagId,
      depthFromFocus
    })
  })

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

    const hidden = !visibleBySearch || (
      state.ui.filterMode === "focused-tags" &&
      state.ui.activeTagsOrdered.length > 0 &&
      !relevantToTags
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
        state.ui.focusedNodeId !== null && (!withinFocus || !incidentToFocus && sourceNode.depthFromFocus >= 1 && targetNode.depthFromFocus >= 1)
      ),
      size: incidentToFocus
        ? 3.1
        : state.ui.focusedNodeId !== null && !withinFocus
          ? 0.9
          : sourceNode.depthFromFocus <= 1 || targetNode.depthFromFocus <= 1
            ? 2.1
            : 1.3,
      type: attributes.type,
      label: roleLabel(attributes.hierRole)
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

    if (state.ui.filterMode === "focused-tags" && state.ui.activeTagsOrdered.length > 0 && !base.priorityTagId) {
      filterState = hasVisibleIncidentEdge ? "ghost" : "hidden"
    }

    const hidden = !base.matchesSearch || filterState === "hidden"
    const size = isFocused ? 14 : base.depthFromFocus === 1 ? 10 : base.depthFromFocus === 2 ? 8.5 : filterState === "ghost" ? 5.5 : 7

    nodeDisplay.set(nodeId, {
      ...base,
      filterState,
      hidden,
      size,
      color: colorForNode(base.priorityTagId, filterState, state.indexes.tagMetaById, isFocused, isHovered),
      labelColor: labelColorForNode(filterState, isFocused, isHovered),
      forceLabel: isFocused || isHovered || base.depthFromFocus <= 1
    })
  })

  return { nodes: nodeDisplay, edges: edgeDisplay }
}
