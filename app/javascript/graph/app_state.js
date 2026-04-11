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
      animationToken: 0,
      cameraAnimationToken: 0,
      cameraAnimationTimeoutId: null,
      manualPositions: new Map()
    },
    ui: {
      focusedNodeId: null,
      pinnedTooltipNodeId: null,
      hoveredNodeId: null,
      activeTagsOrdered: [],
      selectedTagIds: [],
      tagSearchQuery: "",
      topN: null,
      filterMode: "all",
      focusDepth: 3,
      enabledRoles: new Set(["target_is_parent", "target_is_child", "same_level", "next_in_sequence", "null"]),
      searchQuery: "",
      draggingNodeId: null,
      draggedNodeMoved: false
    }
  }
}
