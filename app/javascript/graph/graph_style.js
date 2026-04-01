export function colorForNode(priorityTag, filterState, tagMetaById, isFocused, isHovered, hoverState, hoverFade = 1) {
  if (isFocused) return "#fde68a"
  if (isHovered) return "#bfdbfe"
  if (hoverState === "moderate") {
    const alpha = 0.55 + (1 - hoverFade) * 0.45
    return `rgba(125, 211, 252, ${alpha.toFixed(2)})`
  }
  if (filterState === "ghost") return "#516178"
  return tagMetaById.get(priorityTag)?.color_hex || "#7dd3fc"
}

export function borderColorForNode(priorityTag, filterState, tagMetaById, isFocused, isHovered, hoverState, hoverFade = 1) {
  if (isFocused) return "#fff7cc"
  if (isHovered) return "#e0f2fe"
  if (hoverState === "moderate") {
    const alpha = 0.55 + (1 - hoverFade) * 0.45
    return `rgba(219, 234, 254, ${alpha.toFixed(2)})`
  }
  if (filterState === "ghost") return "#94a3b8"
  return tagMetaById.get(priorityTag)?.color_hex || "#dbeafe"
}

export function labelColorForNode(filterState, isFocused, isHovered, hoverState, hoverFade = 1) {
  if (isFocused) return "#fff7cc"
  if (isHovered) return "#f8fafc"
  if (hoverState === "moderate") {
    const alpha = 0.55 + (1 - hoverFade) * 0.45
    return `rgba(248, 250, 252, ${alpha.toFixed(2)})`
  }
  if (filterState === "ghost") return "#cbd5e1"
  return "#f8fafc"
}

export function colorForEdge(priorityTag, hierRole, tagMetaById, isFocusDepth1, isFocusDepth2, isGhost) {
  if (isGhost) return "rgba(100, 116, 139, 0.32)"
  const semanticColor = priorityTag
    ? (tagMetaById.get(priorityTag)?.color_hex || "#94a3b8")
    : baseEdgeColor(hierRole)

  if (isFocusDepth1) return mixHexColors(semanticColor, "#ffffff", 0.35)
  if (isFocusDepth2) return mixHexColors(semanticColor, "#ffffff", 0.18)
  return semanticColor
}

export function roleLabel(hierRole) {
  if (hierRole === "target_is_parent") return "target = pai"
  if (hierRole === "target_is_child") return "target = filho"
  if (hierRole === "same_level") return "mesmo nivel"
  return "sem classificacao"
}

function baseEdgeColor(hierRole) {
  if (hierRole === "target_is_parent") return "#f97316"
  if (hierRole === "target_is_child") return "#0ea5e9"
  if (hierRole === "same_level") return "#84cc16"
  return "#64748b"
}

function mixHexColors(colorA, colorB, ratio) {
  const normalizedRatio = Math.max(0, Math.min(1, ratio))
  const [r1, g1, b1] = hexToRgb(colorA)
  const [r2, g2, b2] = hexToRgb(colorB)

  const r = Math.round(r1 + ((r2 - r1) * normalizedRatio))
  const g = Math.round(g1 + ((g2 - g1) * normalizedRatio))
  const b = Math.round(b1 + ((b2 - b1) * normalizedRatio))

  return `rgb(${r}, ${g}, ${b})`
}

function hexToRgb(hex) {
  const normalized = String(hex).replace("#", "")
  const full = normalized.length === 3
    ? normalized.split("").map((char) => `${char}${char}`).join("")
    : normalized

  return [
    Number.parseInt(full.slice(0, 2), 16),
    Number.parseInt(full.slice(2, 4), 16),
    Number.parseInt(full.slice(4, 6), 16)
  ]
}
