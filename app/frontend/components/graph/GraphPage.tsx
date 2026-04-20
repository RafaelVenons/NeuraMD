import { useNavigate } from "react-router-dom"

import { GraphCanvas } from "~/components/graph/GraphCanvas"
import { useGraphData } from "~/components/graph/useGraphData"
import { useTentacleRuntime } from "~/components/graph/useTentacleRuntime"

export function GraphPage() {
  const state = useGraphData()
  const aliveTentacleIds = useTentacleRuntime()
  const navigate = useNavigate()

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

  const { dataset, nodes, edges } = state
  const counts = countByType(nodes)

  return (
    <div className="nm-graph-page">
      <aside className="nm-graph-page__rail">
        <header>
          <h2>Grafo</h2>
          <p className="nm-graph-page__muted">
            {dataset.meta.note_count} notas · {dataset.meta.link_count} links
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

function countByType(nodes: { type: "root" | "structure" | "leaf" | "tentacle" }[]) {
  return nodes.reduce(
    (acc, node) => {
      acc[node.type] += 1
      return acc
    },
    { root: 0, structure: 0, leaf: 0, tentacle: 0 }
  )
}
