import { useEffect, useRef, useState } from "react"

import type { GraphEdge, GraphNode, NodeType } from "~/components/graph/types"
import { DEFAULT_FORCE_PARAMS, useForceSimulation } from "~/components/graph/useForceSimulation"

type Props = {
  nodes: GraphNode[]
  edges: GraphEdge[]
  onSelectNote?: (slug: string) => void
  selectedId?: string | null
  aliveTentacleIds?: Set<string>
}

const NODE_COLOR: Record<NodeType, string> = {
  root: "#ffb347",
  structure: "#5cc8ff",
  leaf: "#c1c5cc",
  tentacle: "#a6e3a1",
}

const NODE_RADIUS: Record<NodeType, number> = {
  root: 14,
  structure: 10,
  leaf: 6,
  tentacle: 9,
}

export function GraphCanvas({ nodes, edges, onSelectNote, selectedId, aliveTentacleIds }: Props) {
  const hostRef = useRef<HTMLDivElement | null>(null)
  const [size, setSize] = useState({ width: 960, height: 640 })

  useEffect(() => {
    const host = hostRef.current
    if (!host) return
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect
        if (width > 0 && height > 0) {
          setSize({ width: Math.floor(width), height: Math.floor(height) })
        }
      }
    })
    ro.observe(host)
    return () => ro.disconnect()
  }, [])

  const { simulatedNodes } = useForceSimulation({
    nodes,
    edges,
    centerX: size.width / 2,
    centerY: size.height / 2,
    params: DEFAULT_FORCE_PARAMS,
  })

  const nodeById = new Map(simulatedNodes.map((n) => [n.id, n]))

  return (
    <div ref={hostRef} className="nm-graph-canvas">
      <svg
        width={size.width}
        height={size.height}
        role="img"
        aria-label="Grafo de notas"
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
                strokeWidth={1}
              />
            )
          })}
        </g>
        <g>
          {simulatedNodes.map((node) => {
            const r = NODE_RADIUS[node.type]
            const isSelected = selectedId === node.id
            const isAliveTentacle = node.type === "tentacle" && aliveTentacleIds?.has(node.id) === true
            return (
              <g
                key={node.id}
                transform={`translate(${node.x}, ${node.y})`}
                onClick={() => onSelectNote?.(node.note.slug)}
                className="nm-graph-canvas__node"
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
                <circle
                  r={r + (isSelected ? 3 : 0)}
                  fill={NODE_COLOR[node.type]}
                  stroke={isSelected ? "#ffffff" : "rgba(0,0,0,0.35)"}
                  strokeWidth={isSelected ? 2 : 1}
                />
                {isAliveTentacle ? (
                  <circle
                    r={2.5}
                    cx={r - 1}
                    cy={-(r - 1)}
                    fill="#a6e3a1"
                    stroke="#0b0d10"
                    strokeWidth={1}
                  >
                    <title>Tentáculo vivo</title>
                  </circle>
                ) : null}
                {node.type === "root" || node.type === "structure" ? (
                  <text
                    x={r + 4}
                    y={4}
                    fill="var(--nm-shell-text)"
                    fontSize={11}
                    pointerEvents="none"
                  >
                    {node.label}
                  </text>
                ) : null}
              </g>
            )
          })}
        </g>
      </svg>
    </div>
  )
}
