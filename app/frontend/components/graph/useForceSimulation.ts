import {
  type Simulation,
  type SimulationLinkDatum,
  type SimulationNodeDatum,
  forceCollide,
  forceLink,
  forceManyBody,
  forceSimulation,
  forceX,
  forceY,
} from "d3-force"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import type { GraphEdge, GraphNode, NodeType } from "~/components/graph/types"

export type ForceParams = {
  repelStrength: number
  repelDistanceMax: number
  linkDistance: number
  linkStrength: number
  positionStrength: number
  collisionPadding: number
  velocityDecay: number
  alphaDecay: number
}

export const DEFAULT_FORCE_PARAMS: ForceParams = {
  repelStrength: -420,
  repelDistanceMax: 640,
  linkDistance: 110,
  linkStrength: 0.22,
  positionStrength: 0.035,
  collisionPadding: 48,
  velocityDecay: 0.4,
  alphaDecay: 0.0228,
}

const ALPHA_MIN = 0.001
const ALPHA_TARGET = 0
const REHEAT_ALPHA = 0.8

type SimNode = SimulationNodeDatum & { _gn: GraphNode }
type SimLink = SimulationLinkDatum<SimNode>

type UseForceSimulationOptions = {
  nodes: GraphNode[]
  edges: GraphEdge[]
  centerX: number
  centerY: number
  params?: ForceParams
}

type UseForceSimulationResult = {
  simulatedNodes: GraphNode[]
  pinNode: (id: string) => void
  unpinNode: (id: string) => void
  moveNode: (id: string, x: number, y: number) => void
  reheat: () => void
}

const LINK_DISTANCE_BY_TYPE: Record<NodeType, number> = {
  root: 1.35,
  structure: 1.1,
  leaf: 1.0,
  tentacle: 0.75,
}

const LINK_STRENGTH_BY_TYPE: Record<NodeType, number> = {
  root: 1.4,
  structure: 1.2,
  leaf: 1.0,
  tentacle: 1.6,
}

export function useForceSimulation({
  nodes,
  edges,
  centerX,
  centerY,
  params = DEFAULT_FORCE_PARAMS,
}: UseForceSimulationOptions): UseForceSimulationResult {
  const simRef = useRef<Simulation<SimNode, SimLink> | null>(null)
  const simNodeMapRef = useRef<Map<string, SimNode>>(new Map())
  const [snapshot, setSnapshot] = useState<GraphNode[]>(nodes)

  const nodesRef = useRef(nodes)
  const edgesRef = useRef(edges)
  const paramsRef = useRef(params)
  nodesRef.current = nodes
  edgesRef.current = edges
  paramsRef.current = params

  const nodeIdKey = useMemo(() => nodes.map((n) => n.id).join("\0"), [nodes])
  const edgeKey = useMemo(
    () => edges.map((e) => `${e.source}\0${e.target}`).join("\0"),
    [edges]
  )

  useEffect(() => {
    void nodeIdKey
    void edgeKey

    const currentNodes = nodesRef.current
    const currentEdges = edgesRef.current
    const p = paramsRef.current

    if (currentNodes.length === 0) {
      simRef.current?.stop()
      simRef.current = null
      simNodeMapRef.current.clear()
      setSnapshot([])
      return
    }

    const prevMap = simNodeMapRef.current
    const simNodes: SimNode[] = currentNodes.map((gn) => {
      const prev = prevMap.get(gn.id)
      if (prev) {
        prev._gn = gn
        return prev
      }
      return {
        _gn: gn,
        x: gn.x,
        y: gn.y,
        vx: gn.vx,
        vy: gn.vy,
        fx: gn.pinned ? gn.x : undefined,
        fy: gn.pinned ? gn.y : undefined,
      }
    })

    const nextMap = new Map<string, SimNode>()
    for (const sn of simNodes) nextMap.set(sn._gn.id, sn)
    simNodeMapRef.current = nextMap

    const simLinks: SimLink[] = currentEdges
      .map((e) => {
        const source = nextMap.get(e.source)
        const target = nextMap.get(e.target)
        if (!source || !target) return null
        return { source, target } as SimLink
      })
      .filter((l): l is SimLink => l !== null)

    const applyForces = (sim: Simulation<SimNode, SimLink>) => {
      sim
        .force(
          "link",
          forceLink<SimNode, SimLink>(simLinks)
            .distance((link: SimLink) => {
              const target = link.target as SimNode
              const factor = LINK_DISTANCE_BY_TYPE[target._gn.type] ?? 1
              return p.linkDistance * factor
            })
            .strength((link: SimLink) => {
              const target = link.target as SimNode
              const factor = LINK_STRENGTH_BY_TYPE[target._gn.type] ?? 1
              return p.linkStrength * factor
            })
        )
        .force(
          "charge",
          forceManyBody<SimNode>().strength(p.repelStrength).distanceMax(p.repelDistanceMax)
        )
        .force("x", forceX<SimNode>(centerX).strength(p.positionStrength))
        .force("y", forceY<SimNode>(centerY).strength(p.positionStrength))
        .force("collide", forceCollide<SimNode>(p.collisionPadding))
    }

    if (simRef.current) {
      simRef.current.nodes(simNodes)
      applyForces(simRef.current)
      simRef.current.alpha(REHEAT_ALPHA).restart()
    } else {
      const sim = forceSimulation<SimNode>(simNodes)
        .velocityDecay(p.velocityDecay)
        .alphaDecay(p.alphaDecay)
        .alphaMin(ALPHA_MIN)
        .alphaTarget(ALPHA_TARGET)

      applyForces(sim)

      sim.on("tick", () => {
        const updated: GraphNode[] = sim.nodes().map((sn) => ({
          ...sn._gn,
          x: sn.x ?? sn._gn.x,
          y: sn.y ?? sn._gn.y,
          vx: sn.vx ?? 0,
          vy: sn.vy ?? 0,
        }))
        setSnapshot(updated)
      })

      simRef.current = sim
    }
  }, [nodeIdKey, edgeKey, centerX, centerY])

  useEffect(() => {
    return () => {
      simRef.current?.stop()
      simRef.current = null
    }
  }, [])

  const pinNode = useCallback((id: string) => {
    const sn = simNodeMapRef.current.get(id)
    if (sn) {
      sn.fx = sn.x
      sn.fy = sn.y
      sn._gn = { ...sn._gn, pinned: true }
    }
  }, [])

  const unpinNode = useCallback((id: string) => {
    const sn = simNodeMapRef.current.get(id)
    if (sn) {
      sn.fx = undefined
      sn.fy = undefined
      sn._gn = { ...sn._gn, pinned: false }
    }
  }, [])

  const moveNode = useCallback((id: string, x: number, y: number) => {
    const sn = simNodeMapRef.current.get(id)
    if (sn) {
      sn.fx = x
      sn.fy = y
      sn.x = x
      sn.y = y
      sn.vx = 0
      sn.vy = 0
    }
  }, [])

  const reheat = useCallback(() => {
    simRef.current?.alpha(REHEAT_ALPHA).restart()
  }, [])

  return { simulatedNodes: snapshot, pinNode, unpinNode, moveNode, reheat }
}
