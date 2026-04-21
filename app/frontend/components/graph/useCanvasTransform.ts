import { useCallback, useEffect, useRef, useState } from "react"

import {
  applyPan,
  applyZoomAroundPoint,
  computeFitTransform,
  screenToGraph as screenToGraphPure,
  type CanvasTransform,
} from "~/components/graph/canvasTransform"

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
      return screenToGraphPure(clientX, clientY, rect, transform)
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
    const direction = e.deltaY < 0 ? 1 : -1
    setTransform((prev) => applyZoomAroundPoint(prev, cx, cy, direction))
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
    setTransform((prev) =>
      applyPan(prev, pan.startTx, pan.startTy, pan.startX, pan.startY, e.clientX, e.clientY)
    )
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
    setTransform((prev) => applyZoomAroundPoint(prev, cx, cy, 1))
  }, [])

  const zoomOut = useCallback(() => {
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    const cx = rect.width / 2
    const cy = rect.height / 2
    setTransform((prev) => applyZoomAroundPoint(prev, cx, cy, -1))
  }, [])

  const fitAll = useCallback((nodes: { x: number; y: number }[]) => {
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    const next = computeFitTransform(nodes, rect)
    if (!next) return
    setTransform(next)
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
