export function drawNodeLabelAbove(context, data, settings) {
  if (!data.label) return

  const label = truncateLabel(String(data.label), 26)
  const fontSize = resolveFontSize(data.size, settings.labelSize || 14)
  const fontFamily = settings.labelFont || "sans-serif"

  context.save()
  context.font = `600 ${fontSize}px ${fontFamily}`
  context.textAlign = "center"
  context.textBaseline = "middle"

  const pillHeight = fontSize + 8
  const pillPaddingX = 8
  const baseY = data.y - data.size - 12
  const textWidth = context.measureText(label).width
  const pillWidth = textWidth + (pillPaddingX * 2)
  const pillX = data.x - (pillWidth / 2)
  const pillY = baseY - pillHeight + 3

  roundRect(context, pillX, pillY, pillWidth, pillHeight, Math.min(10, pillHeight / 2))
  context.fillStyle = "rgba(15, 23, 42, 0.88)"
  context.fill()

  context.lineWidth = 1
  context.strokeStyle = "rgba(148, 163, 184, 0.35)"
  context.stroke()

  context.fillStyle = data.labelColor || "#f8fafc"
  context.fillText(label, data.x, pillY + (pillHeight / 2) + 0.5)
  context.restore()
}

function resolveFontSize(nodeSize, fallbackSize) {
  const base = typeof fallbackSize === "number" ? fallbackSize : 14
  return Math.max(12, Math.min(16, Math.round(base * 0.78 + nodeSize * 0.22)))
}

function truncateLabel(label, maxLength) {
  if (label.length <= maxLength) return label
  return `${label.slice(0, Math.max(0, maxLength - 1))}…`
}

function roundRect(context, x, y, width, height, radius) {
  context.beginPath()
  context.moveTo(x + radius, y)
  context.lineTo(x + width - radius, y)
  context.quadraticCurveTo(x + width, y, x + width, y + radius)
  context.lineTo(x + width, y + height - radius)
  context.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  context.lineTo(x + radius, y + height)
  context.quadraticCurveTo(x, y + height, x, y + height - radius)
  context.lineTo(x, y + radius)
  context.quadraticCurveTo(x, y, x + radius, y)
  context.closePath()
}
