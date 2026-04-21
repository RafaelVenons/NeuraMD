export type CanvasTransform = {
  translateX: number
  translateY: number
  scale: number
}

export type ViewportRect = {
  width: number
  height: number
  left?: number
  top?: number
}

export const MIN_SCALE = 0.15
export const MAX_SCALE = 4.0
export const ZOOM_FACTOR = 0.12
export const FIT_PADDING = 80

export function clampScale(scale: number): number {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale))
}

export function applyZoomAroundPoint(
  prev: CanvasTransform,
  cx: number,
  cy: number,
  direction: 1 | -1
): CanvasTransform {
  const factor = 1 + direction * ZOOM_FACTOR
  const nextScale = clampScale(prev.scale * factor)
  const ratio = nextScale / prev.scale
  return {
    scale: nextScale,
    translateX: cx - (cx - prev.translateX) * ratio,
    translateY: cy - (cy - prev.translateY) * ratio,
  }
}

export function screenToGraph(
  clientX: number,
  clientY: number,
  rect: ViewportRect,
  transform: CanvasTransform
): { x: number; y: number } {
  const left = rect.left ?? 0
  const top = rect.top ?? 0
  return {
    x: (clientX - left - transform.translateX) / transform.scale,
    y: (clientY - top - transform.translateY) / transform.scale,
  }
}

export function computeFitTransform(
  nodes: { x: number; y: number }[],
  rect: ViewportRect
): CanvasTransform | null {
  if (nodes.length === 0) return null
  if (rect.width === 0 || rect.height === 0) return null

  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const n of nodes) {
    if (n.x < minX) minX = n.x
    if (n.y < minY) minY = n.y
    if (n.x > maxX) maxX = n.x
    if (n.y > maxY) maxY = n.y
  }
  const graphW = Math.max(1, maxX - minX)
  const graphH = Math.max(1, maxY - minY)
  const scaleX = (rect.width - FIT_PADDING * 2) / graphW
  const scaleY = (rect.height - FIT_PADDING * 2) / graphH
  const scale = clampScale(Math.min(scaleX, scaleY))
  const cgx = (minX + maxX) / 2
  const cgy = (minY + maxY) / 2
  return {
    scale,
    translateX: rect.width / 2 - cgx * scale,
    translateY: rect.height / 2 - cgy * scale,
  }
}

export function applyPan(
  prev: CanvasTransform,
  startTx: number,
  startTy: number,
  startX: number,
  startY: number,
  currentX: number,
  currentY: number
): CanvasTransform {
  return {
    ...prev,
    translateX: startTx + (currentX - startX),
    translateY: startTy + (currentY - startY),
  }
}
