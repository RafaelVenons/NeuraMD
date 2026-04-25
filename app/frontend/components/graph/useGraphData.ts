import { useEffect, useMemo, useState } from "react"

import { ApiError } from "~/runtime/errors"
import { fetchJson } from "~/runtime/fetchJson"
import type { GraphDataset, GraphEdge, GraphNode } from "~/components/graph/types"

export type GraphDataState =
  | { status: "loading" }
  | { status: "ready"; dataset: GraphDataset; nodes: GraphNode[]; edges: GraphEdge[] }
  | { status: "error"; error: ApiError | Error }

export function useGraphData(url = "/api/graph", refreshKey: number = 0): GraphDataState {
  const [state, setState] = useState<GraphDataState>({ status: "loading" })

  useEffect(() => {
    let cancelled = false

    fetchJson<GraphDataset>(url)
      .then((dataset) => {
        if (cancelled) return
        const { nodes, edges } = normalizeDataset(dataset)
        setState({ status: "ready", dataset, nodes, edges })
      })
      .catch((error: unknown) => {
        if (cancelled) return
        setState({
          status: "error",
          error: error instanceof Error ? error : new Error(String(error)),
        })
      })

    return () => {
      cancelled = true
    }
  }, [url, refreshKey])

  return state
}

export function normalizeDataset(dataset: GraphDataset): { nodes: GraphNode[]; edges: GraphEdge[] } {
  const count = dataset.notes.length
  const radius = Math.max(240, Math.sqrt(count) * 80)

  const nodes: GraphNode[] = dataset.notes.map((note, index) => {
    const angle = (index / Math.max(1, count)) * Math.PI * 2
    return {
      id: note.id,
      label: note.title,
      type: note.node_type,
      x: Math.cos(angle) * radius,
      y: Math.sin(angle) * radius,
      note,
    }
  })

  const edges: GraphEdge[] = dataset.links.map((link) => ({
    id: link.id,
    source: link.src_note_id,
    target: link.dst_note_id,
    role: link.hier_role ?? null,
  }))

  return { nodes, edges }
}

export function useCenteredViewport(width: number, height: number) {
  return useMemo(() => ({ centerX: width / 2, centerY: height / 2 }), [width, height])
}
