import { useCallback, useRef, useState } from "react"

import { ClawdAvatar } from "~/components/graph/ClawdAvatar"
import { DEFAULT_AGENT_COLOR } from "~/components/graph/agentPalette"
import type { GraphEdge, GraphNode, NodeType } from "~/components/graph/types"
import { DEFAULT_FORCE_PARAMS, useForceSimulation } from "~/components/graph/useForceSimulation"
import { useCanvasTransform } from "~/components/graph/useCanvasTransform"

type Props = {
  nodes: GraphNode[]
  edges: GraphEdge[]
  onSelectNote?: (slug: string) => void
  // When provided, agent clicks invoke this instead of `onSelectNote`.
  // Lets the host (GraphPage) open the avatar editor in place of navigating.
  onAgentClick?: (node: GraphNode, screen: { x: number; y: number }) => void
  selectedId?: string | null
  aliveTentacleIds?: Set<string>
  agentNoteIds?: Set<string>
  agentColors?: Map<string, string>
  awakeAgentIds?: Set<string>
}

const NODE_COLOR: Record<NodeType, string> = {
  root: "#ffb347",
  structure: "#5cc8ff",
  leaf: "#c1c5cc",
  tentacle: "#a6e3a1",
}

const AGENT_AVATAR_SIZE = 26

const NODE_RADIUS: Record<NodeType, number> = {
  root: 14,
  structure: 10,
  leaf: 6,
  tentacle: 9,
}

const CLICK_THRESHOLD = 4

export function GraphCanvas({
  nodes,
  edges,
  onSelectNote,
  onAgentClick,
  selectedId,
  aliveTentacleIds,
  agentNoteIds,
  agentColors,
  awakeAgentIds,
}: Props) {
  const {
    transform,
    isPanning,
    svgRef,
    handleWheel,
    handlePointerDown: handleCanvasPointerDown,
    handlePointerMove: handleCanvasPointerMove,
    handlePointerUp: handleCanvasPointerUp,
    screenToGraph,
    zoomIn,
    zoomOut,
    fitAll,
  } = useCanvasTransform()

  const { simulatedNodes, pinNode, unpinNode, moveNode, reheat } = useForceSimulation({
    nodes,
    edges,
    centerX: 0,
    centerY: 0,
    params: DEFAULT_FORCE_PARAMS,
  })

  const [dragNodeId, setDragNodeId] = useState<string | null>(null)
  const dragStartRef = useRef<{ x: number; y: number } | null>(null)

  const handleNodePointerDown = useCallback(
    (e: React.PointerEvent<SVGGElement>, nodeId: string) => {
      if (e.button !== 0) return
      e.stopPropagation()
      dragStartRef.current = { x: e.clientX, y: e.clientY }
      setDragNodeId(nodeId)
      pinNode(nodeId)
      svgRef.current?.setPointerCapture?.(e.pointerId)
    },
    [pinNode, svgRef]
  )

  const handleSvgPointerMove = useCallback(
    (e: React.PointerEvent<SVGSVGElement>) => {
      if (dragNodeId) {
        const pos = screenToGraph(e.clientX, e.clientY)
        moveNode(dragNodeId, pos.x, pos.y)
        return
      }
      handleCanvasPointerMove(e)
    },
    [dragNodeId, screenToGraph, moveNode, handleCanvasPointerMove]
  )

  const handleSvgPointerUp = useCallback(
    (e: React.PointerEvent<SVGSVGElement>) => {
      if (dragNodeId) {
        const start = dragStartRef.current
        const dx = start ? e.clientX - start.x : Infinity
        const dy = start ? e.clientY - start.y : Infinity
        const wasClick = Math.abs(dx) < CLICK_THRESHOLD && Math.abs(dy) < CLICK_THRESHOLD
        unpinNode(dragNodeId)
        reheat()
        if (wasClick) {
          const node = simulatedNodes.find((n) => n.id === dragNodeId)
          if (node) {
            const isAgent = agentNoteIds?.has(node.id) === true
            if (isAgent && onAgentClick) {
              onAgentClick(node, { x: e.clientX, y: e.clientY })
            } else {
              onSelectNote?.(node.note.slug)
            }
          }
        }
        setDragNodeId(null)
        dragStartRef.current = null
        return
      }
      handleCanvasPointerUp(e)
    },
    [
      dragNodeId,
      unpinNode,
      reheat,
      handleCanvasPointerUp,
      simulatedNodes,
      onSelectNote,
      onAgentClick,
      agentNoteIds,
    ]
  )

  const nodeById = new Map(simulatedNodes.map((n) => [n.id, n]))

  return (
    <div className="nm-graph-canvas">
      <div className="nm-graph-canvas__controls">
        <button type="button" onClick={zoomOut} aria-label="Diminuir zoom">−</button>
        <button type="button" onClick={zoomIn} aria-label="Aumentar zoom">+</button>
        <button
          type="button"
          onClick={() => fitAll(simulatedNodes)}
          aria-label="Ajustar ao grafo"
          title="Ajustar"
        >
          ⤢
        </button>
      </div>
      <svg
        ref={svgRef}
        role="img"
        aria-label="Grafo de notas"
        className={`nm-graph-canvas__svg${isPanning || dragNodeId ? " is-panning" : ""}`}
        onWheel={handleWheel}
        onPointerDown={handleCanvasPointerDown}
        onPointerMove={handleSvgPointerMove}
        onPointerUp={handleSvgPointerUp}
        onPointerCancel={handleSvgPointerUp}
      >
        <g
          transform={`translate(${transform.translateX}, ${transform.translateY}) scale(${transform.scale})`}
        >
          <g>
            {edges.map((edge) => {
              const source = nodeById.get(edge.source)
              const target = nodeById.get(edge.target)
              if (!source || !target) return null
              return (
                <line
                  key={edge.id}
                  x1={source.x}
                  y1={source.y}
                  x2={target.x}
                  y2={target.y}
                  stroke="rgba(255,255,255,0.12)"
                  strokeWidth={1 / transform.scale}
                />
              )
            })}
          </g>
          <g>
            {simulatedNodes.map((node) => {
              const isAgent = agentNoteIds?.has(node.id) === true
              const r = NODE_RADIUS[node.type]
              const isSelected = selectedId === node.id
              const isAliveTentacle = node.type === "tentacle" && aliveTentacleIds?.has(node.id) === true
              const showLabel = isAgent || node.type === "root" || node.type === "structure"
              const avatar = isAgent ? node.note.avatar ?? null : null
              const avatarColor =
                avatar?.color || (isAgent && agentColors?.get(node.id)) || DEFAULT_AGENT_COLOR
              const avatarState =
                avatar?.state ?? (isAgent && awakeAgentIds?.has(node.id) ? "awake" : "sleeping")
              const avatarHat = avatar?.hat ?? "none"
              const labelOffset = isAgent ? AGENT_AVATAR_SIZE / 2 + 4 : r + 4
              return (
                <g
                  key={node.id}
                  transform={`translate(${node.x}, ${node.y})`}
                  onPointerDown={(e) => handleNodePointerDown(e, node.id)}
                  className="nm-graph-canvas__node"
                  data-agent={isAgent ? "true" : undefined}
                  data-agent-state={isAgent ? avatarState : undefined}
                >
                  {isAliveTentacle ? (
                    <circle
                      r={r + 5}
                      fill="none"
                      stroke="#a6e3a1"
                      strokeWidth={1.5}
                      strokeOpacity={0.7}
                      className="nm-graph-canvas__pulse"
                    />
                  ) : null}
                  {isAgent ? (
                    <>
                      {isSelected ? (
                        <rect
                          x={-AGENT_AVATAR_SIZE / 2 - 2}
                          y={-AGENT_AVATAR_SIZE / 2 - 2}
                          width={AGENT_AVATAR_SIZE + 4}
                          height={AGENT_AVATAR_SIZE + 4}
                          rx={4}
                          fill="none"
                          stroke="#ffffff"
                          strokeWidth={2}
                        />
                      ) : null}
                      <ClawdAvatar
                        state={avatarState}
                        color={avatarColor}
                        hat={avatarHat}
                        size={AGENT_AVATAR_SIZE}
                        animateZzz
                      />
                    </>
                  ) : (
                    <circle
                      r={r + (isSelected ? 3 : 0)}
                      fill={NODE_COLOR[node.type]}
                      stroke={isSelected ? "#ffffff" : "rgba(0,0,0,0.35)"}
                      strokeWidth={isSelected ? 2 : 1}
                    />
                  )}
                  {isAliveTentacle ? (
                    <circle r={2.5} cx={r - 1} cy={-(r - 1)} fill="#a6e3a1" stroke="#0b0d10" strokeWidth={1}>
                      <title>Tentáculo vivo</title>
                    </circle>
                  ) : null}
                  {showLabel ? (
                    <text
                      x={labelOffset}
                      y={4}
                      fill="var(--nm-shell-text)"
                      fontSize={11 / transform.scale}
                      pointerEvents="none"
                    >
                      {node.label}
                    </text>
                  ) : null}
                </g>
              )
            })}
          </g>
        </g>
      </svg>
    </div>
  )
}
