import { useMemo, useState } from "react"
import { useNavigate } from "react-router-dom"

import { GraphCanvas } from "~/components/graph/GraphCanvas"
import { useGraphData } from "~/components/graph/useGraphData"
import { useTentacleRuntime } from "~/components/graph/useTentacleRuntime"
import type { GraphEdge, GraphNode, NodeType } from "~/components/graph/types"

export function GraphPage() {
  const state = useGraphData()
  const aliveTentacleIds = useTentacleRuntime()
  const navigate = useNavigate()
  const [selectedTagIds, setSelectedTagIds] = useState<Set<string>>(() => new Set())

  const toggleTag = (id: string) => {
    setSelectedTagIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const filtered = useMemo(() => {
    if (state.status !== "ready") return null
    return filterGraph(state.nodes, state.edges, state.dataset.noteTags, selectedTagIds)
  }, [state, selectedTagIds])

  if (state.status === "loading") {
    return <div className="nm-graph-page__status">Carregando grafo…</div>
  }

  if (state.status === "error") {
    return (
      <div className="nm-graph-page__status nm-graph-page__status--error">
        Erro ao carregar grafo: {state.error.message}
      </div>
    )
  }

  const { dataset } = state
  const { nodes, edges } = filtered ?? { nodes: state.nodes, edges: state.edges }
  const counts = countByType(nodes)
  const tagCounts = tagUsageCounts(dataset.noteTags, new Set(nodes.map((n) => n.id)))
  const sortedTags = [...dataset.tags].sort((a, b) => (tagCounts.get(b.id) ?? 0) - (tagCounts.get(a.id) ?? 0))

  return (
    <div className="nm-graph-page">
      <aside className="nm-graph-page__rail">
        <header>
          <h2>Grafo</h2>
          <p className="nm-graph-page__muted">
            {nodes.length} de {dataset.meta.note_count} notas · {edges.length} links
          </p>
        </header>
        <dl className="nm-graph-page__legend">
          <div data-type="root">
            <dt>Raiz</dt>
            <dd>{counts.root}</dd>
          </div>
          <div data-type="structure">
            <dt>Estrutura</dt>
            <dd>{counts.structure}</dd>
          </div>
          <div data-type="leaf">
            <dt>Folha</dt>
            <dd>{counts.leaf}</dd>
          </div>
          <div data-type="tentacle">
            <dt>Tentáculo</dt>
            <dd>{counts.tentacle}</dd>
          </div>
        </dl>

        <div className="nm-graph-page__section">
          <h3 className="nm-graph-page__section-title">Tags</h3>
          {selectedTagIds.size > 0 ? (
            <button
              type="button"
              className="nm-graph-page__tag-clear"
              onClick={() => setSelectedTagIds(new Set())}
            >
              Limpar ({selectedTagIds.size})
            </button>
          ) : null}
          <div className="nm-graph-page__tags">
            {sortedTags.map((tag) => {
              const count = tagCounts.get(tag.id) ?? 0
              const active = selectedTagIds.has(tag.id)
              return (
                <button
                  key={tag.id}
                  type="button"
                  className={`nm-graph-page__tag${active ? " is-active" : ""}`}
                  onClick={() => toggleTag(tag.id)}
                  title={tag.name}
                >
                  {tag.name}
                  <span className="nm-graph-page__tag-count">{count}</span>
                </button>
              )
            })}
          </div>
        </div>
      </aside>
      <section className="nm-graph-page__canvas">
        <GraphCanvas
          nodes={nodes}
          edges={edges}
          aliveTentacleIds={aliveTentacleIds}
          onSelectNote={(slug) => navigate(`/notes/${slug}`)}
        />
      </section>
    </div>
  )
}

function countByType(nodes: { type: NodeType }[]) {
  return nodes.reduce(
    (acc, node) => {
      acc[node.type] += 1
      return acc
    },
    { root: 0, structure: 0, leaf: 0, tentacle: 0 }
  )
}

function filterGraph(
  nodes: GraphNode[],
  edges: GraphEdge[],
  noteTags: { note_id: string; tag_id: string }[],
  selected: Set<string>
): { nodes: GraphNode[]; edges: GraphEdge[] } {
  if (selected.size === 0) return { nodes, edges }

  const noteTagIndex = new Map<string, Set<string>>()
  for (const nt of noteTags) {
    let set = noteTagIndex.get(nt.note_id)
    if (!set) {
      set = new Set()
      noteTagIndex.set(nt.note_id, set)
    }
    set.add(nt.tag_id)
  }

  const includedIds = new Set<string>()
  const filteredNodes = nodes.filter((node) => {
    const tags = noteTagIndex.get(node.id)
    if (!tags) return false
    for (const tagId of selected) if (tags.has(tagId)) {
      includedIds.add(node.id)
      return true
    }
    return false
  })

  const filteredEdges = edges.filter((e) => includedIds.has(e.source) && includedIds.has(e.target))
  return { nodes: filteredNodes, edges: filteredEdges }
}

function tagUsageCounts(
  noteTags: { note_id: string; tag_id: string }[],
  visibleNoteIds: Set<string>
): Map<string, number> {
  const counts = new Map<string, number>()
  for (const nt of noteTags) {
    if (!visibleNoteIds.has(nt.note_id)) continue
    counts.set(nt.tag_id, (counts.get(nt.tag_id) ?? 0) + 1)
  }
  return counts
}
