export function colorForNode(priorityTag, filterState, tagMetaById, isFocused, isHovered) {
  if (isFocused) return "#fde68a"
  if (isHovered) return "#bfdbfe"
  if (filterState === "ghost") return "#3f4c61"
  return tagMetaById.get(priorityTag)?.color_hex || "#7dd3fc"
}

export function colorForEdge(priorityTag, hierRole, tagMetaById, isFocusDepth1, isFocusDepth2) {
  if (priorityTag) return tagMetaById.get(priorityTag)?.color_hex || "#94a3b8"
  if (isFocusDepth1) return "#f8fafc"
  if (isFocusDepth2) return "#94a3b8"
  if (hierRole === "target_is_parent") return "#f97316"
  if (hierRole === "target_is_child") return "#0ea5e9"
  if (hierRole === "same_level") return "#84cc16"
  return "#64748b"
}

export function roleLabel(hierRole) {
  if (hierRole === "target_is_parent") return "target = pai"
  if (hierRole === "target_is_child") return "target = filho"
  if (hierRole === "same_level") return "mesmo nivel"
  return "sem classificacao"
}
