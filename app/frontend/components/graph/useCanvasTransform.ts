import { useCallback, useEffect, useRef, useState } from "react"

type CanvasTransform = {
  translateX: number
  translateY: number
  scale: number
}

const MIN_SCALE = 0.15
const MAX_SCALE = 4.0
const ZOOM_FACTOR = 0.12

type Result = {
  transform: CanvasTransform
  isPanning: boolean
  svgRef: React.RefObject<SVGSVGElement | null>
  handleWheel: (e: React.WheelEvent<SVGSVGElement>) => void
  handlePointerDown: (e: React.PointerEvent<SVGSVGElement>) => void
  handlePointerMove: (e: React.PointerEvent<SVGSVGElement>) => void
  handlePointerUp: (e: React.PointerEvent<SVGSVGElement>) => void
  screenToGraph: (clientX: number, clientY: number) => { x: number; y: number }
  zoomIn: () => void
  zoomOut: () => void
  fitAll: (nodes: { x: number; y: number }[]) => void
}

export function useCanvasTransform(): Result {
  const svgRef = useRef<SVGSVGElement | null>(null)
  const [transform, setTransform] = useState<CanvasTransform>({
    translateX: 0,
    translateY: 0,
    scale: 1,
  })
  const centeredRef = useRef(false)

  useEffect(() => {
    if (centeredRef.current) return
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    if (rect.width === 0 || rect.height === 0) return
    centeredRef.current = true
    setTransform({ scale: 1, translateX: rect.width / 2, translateY: rect.height / 2 })
  })

  const prevSizeRef = useRef<{ width: number; height: number } | null>(null)
  useEffect(() => {
    const svg = svgRef.current
    if (!svg) return
    const ro = new ResizeObserver((entries) => {
      const entry = entries[0]
      if (!entry) return
      const { width, height } = entry.contentRect
      if (width === 0 || height === 0) return
      const prev = prevSizeRef.current
      if (prev && (Math.abs(prev.width - width) > 1 || Math.abs(prev.height - height) > 1)) {
        setTransform((t) => ({
          ...t,
          translateX: t.translateX + (width - prev.width) / 2,
          translateY: t.translateY + (height - prev.height) / 2,
        }))
      }
      prevSizeRef.current = { width, height }
    })
    ro.observe(svg)
    return () => ro.disconnect()
  }, [])

  const [isPanning, setIsPanning] = useState(false)
  const panState = useRef<{ startX: number; startY: number; startTx: number; startTy: number } | null>(null)

  const screenToGraph = useCallback(
    (clientX: number, clientY: number) => {
      const svg = svgRef.current
      if (!svg) return { x: clientX, y: clientY }
      const rect = svg.getBoundingClientRect()
      return {
        x: (clientX - rect.left - transform.translateX) / transform.scale,
        y: (clientY - rect.top - transform.translateY) / transform.scale,
      }
    },
    [transform]
  )

  const handleWheel = useCallback((e: React.WheelEvent<SVGSVGElement>) => {
    e.preventDefault()
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    const cx = e.clientX - rect.left
    const cy = e.clientY - rect.top

    setTransform((prev) => {
      const direction = e.deltaY < 0 ? 1 : -1
      const factor = 1 + direction * ZOOM_FACTOR
      const nextScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, prev.scale * factor))
      const ratio = nextScale / prev.scale
      return {
        scale: nextScale,
        translateX: cx - (cx - prev.translateX) * ratio,
        translateY: cy - (cy - prev.translateY) * ratio,
      }
    })
  }, [])

  const handlePointerDown = useCallback(
    (e: React.PointerEvent<SVGSVGElement>) => {
      if (e.button !== 0) return
      const target = e.target as Element
      if (target.closest?.(".nm-graph-canvas__node")) return
      panState.current = {
        startX: e.clientX,
        startY: e.clientY,
        startTx: transform.translateX,
        startTy: transform.translateY,
      }
      setIsPanning(true)
      ;(e.currentTarget as SVGSVGElement).setPointerCapture?.(e.pointerId)
    },
    [transform.translateX, transform.translateY]
  )

  const handlePointerMove = useCallback((e: React.PointerEvent<SVGSVGElement>) => {
    const pan = panState.current
    if (!pan) return
    setTransform((prev) => ({
      ...prev,
      translateX: pan.startTx + (e.clientX - pan.startX),
      translateY: pan.startTy + (e.clientY - pan.startY),
    }))
  }, [])

  const handlePointerUp = useCallback(() => {
    panState.current = null
    setIsPanning(false)
  }, [])

  const zoomIn = useCallback(() => {
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    const cx = rect.width / 2
    const cy = rect.height / 2
    setTransform((prev) => {
      const nextScale = Math.min(MAX_SCALE, prev.scale * (1 + ZOOM_FACTOR))
      const ratio = nextScale / prev.scale
      return { scale: nextScale, translateX: cx - (cx - prev.translateX) * ratio, translateY: cy - (cy - prev.translateY) * ratio }
    })
  }, [])

  const zoomOut = useCallback(() => {
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    const cx = rect.width / 2
    const cy = rect.height / 2
    setTransform((prev) => {
      const nextScale = Math.max(MIN_SCALE, prev.scale * (1 - ZOOM_FACTOR))
      const ratio = nextScale / prev.scale
      return { scale: nextScale, translateX: cx - (cx - prev.translateX) * ratio, translateY: cy - (cy - prev.translateY) * ratio }
    })
  }, [])

  const fitAll = useCallback((nodes: { x: number; y: number }[]) => {
    const svg = svgRef.current
    if (!svg || nodes.length === 0) return
    const rect = svg.getBoundingClientRect()
    if (rect.width === 0 || rect.height === 0) return
    let minX = Infinity,
      minY = Infinity,
      maxX = -Infinity,
      maxY = -Infinity
    for (const n of nodes) {
      if (n.x < minX) minX = n.x
      if (n.y < minY) minY = n.y
      if (n.x > maxX) maxX = n.x
      if (n.y > maxY) maxY = n.y
    }
    const graphW = Math.max(1, maxX - minX)
    const graphH = Math.max(1, maxY - minY)
    const padding = 80
    const scaleX = (rect.width - padding * 2) / graphW
    const scaleY = (rect.height - padding * 2) / graphH
    const scale = Math.min(Math.max(Math.min(scaleX, scaleY), MIN_SCALE), MAX_SCALE)
    const cgx = (minX + maxX) / 2
    const cgy = (minY + maxY) / 2
    setTransform({
      scale,
      translateX: rect.width / 2 - cgx * scale,
      translateY: rect.height / 2 - cgy * scale,
    })
  }, [])

  return {
    transform,
    isPanning,
    svgRef,
    handleWheel,
    handlePointerDown,
    handlePointerMove,
    handlePointerUp,
    screenToGraph,
    zoomIn,
    zoomOut,
    fitAll,
  }
}
