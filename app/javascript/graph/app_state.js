export function createAppState() {
  return {
    dataset: null,
    graph: null,
    renderer: null,
    indexes: null,
    display: {
      nodes: new Map(),
      edges: new Map()
    },
    layout: {
      basePositions: null,
      animationToken: 0
    },
    ui: {
      focusedNodeId: null,
      pinnedTooltipNodeId: null,
      hoveredNodeId: null,
      activeTagsOrdered: [],
      topN: null,
      filterMode: "all",
      focusDepth: 3,
      enabledRoles: new Set(["target_is_parent", "target_is_child", "same_level", "null"]),
      searchQuery: ""
    }
  }
}
