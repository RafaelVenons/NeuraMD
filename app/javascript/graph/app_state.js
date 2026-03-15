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
    ui: {
      focusedNodeId: null,
      pinnedTooltipNodeId: null,
      hoveredNodeId: null,
      activeTagsOrdered: [],
      topN: 3,
      filterMode: "all",
      focusDepth: 2,
      enabledRoles: new Set(["target_is_parent", "target_is_child", "same_level", "null"]),
      searchQuery: ""
    }
  }
}
