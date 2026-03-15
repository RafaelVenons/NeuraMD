export function colorForNode(priorityTag, filterState, tagMetaById, isFocused, isHovered) {
  if (isFocused) return "#fde68a"
  if (isHovered) return "#bfdbfe"
  if (filterState === "ghost") return "#516178"
  return tagMetaById.get(priorityTag)?.color_hex || "#7dd3fc"
}

export function labelColorForNode(filterState, isFocused, isHovered) {
  if (isFocused) return "#fff7cc"
  if (isHovered) return "#f8fafc"
  if (filterState === "ghost") return "#cbd5e1"
  return "#f8fafc"
}

export function colorForEdge(priorityTag, hierRole, tagMetaById, isFocusDepth1, isFocusDepth2, isGhost) {
  if (isGhost) return "rgba(100, 116, 139, 0.32)"
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
