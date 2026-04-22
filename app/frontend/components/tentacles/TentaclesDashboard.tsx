import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react"
import { Link } from "react-router-dom"

import { AgentStateBadge } from "~/components/tentacles/AgentStateBadge"
import { selectDashboardLayout } from "~/components/tentacles/dashboardLayout"
import { TentacleMiniPanel } from "~/components/tentacles/TentacleMiniPanel"
import type { TentacleSession, TentacleSessionsIndex } from "~/components/tentacles/types"
import { GraphCanvas } from "~/components/graph/GraphCanvas"
import { agentNoteIds } from "~/components/graph/graphFilters"
import { useGraphData } from "~/components/graph/useGraphData"
import { fetchJson } from "~/runtime/fetchJson"
import { runtimeStateStore } from "~/runtime/runtimeStateStore"

type Status = "loading" | "idle" | "error"

export function TentaclesDashboard() {
  const [sessions, setSessions] = useState<TentacleSession[]>([])
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)
  const [focusedId, setFocusedId] = useState<string | null>(null)

  const runtimeStates = useSyncExternalStore(
    runtimeStateStore.subscribe,
    runtimeStateStore.getSnapshot,
    runtimeStateStore.getSnapshot
  )

  const load = useCallback(async () => {
    setStatus("loading")
    setMessage(null)
    try {
      const res = await fetchJson<TentacleSessionsIndex>("/api/tentacles/sessions")
      setSessions(res.sessions)
      setStatus("idle")
    } catch (err) {
      setStatus("error")
      setMessage(err instanceof Error ? err.message : "Erro ao carregar sessões")
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const handleRemoved = useCallback((tentacleId: string) => {
    setSessions((prev) => prev.filter((s) => s.tentacle_id !== tentacleId))
    setFocusedId((current) => (current === tentacleId ? null : current))
    runtimeStateStore.remove(tentacleId)
  }, [])

  const layout = useMemo(
    () => selectDashboardLayout({ sessions, focusedId, runtimeStates }),
    [sessions, focusedId, runtimeStates]
  )

  return (
    <section className="nm-tentacles-dashboard">
      <header className="nm-tentacles-dashboard__header">
        <div>
          <h1>Tentáculos ativos</h1>
          <p className="nm-tentacles-dashboard__meta">
            {status === "loading"
              ? "Carregando…"
              : `${sessions.length} sessão(ões) vivas${
                  layout.needsAttention.length > 0
                    ? ` · ${layout.needsAttention.length} aguardando você`
                    : ""
                }`}
          </p>
        </div>
        <button
          type="button"
          className="nm-button"
          onClick={() => void load()}
          disabled={status === "loading"}
        >
          Atualizar
        </button>
      </header>

      {status === "error" && message ? (
        <p className="nm-tentacles-dashboard__error">{message}</p>
      ) : null}

      {status === "idle" && sessions.length === 0 ? (
        <p className="nm-tentacles-dashboard__empty">
          Nenhum tentáculo vivo. Abra uma nota e inicie um em <code>/app/notes/:slug/tentacle</code>.
        </p>
      ) : null}

      {layout.focused ? (
        <div className="nm-tentacles-dashboard__layout">
          <div className="nm-tentacles-dashboard__main">
            <TentacleMiniPanel
              key={layout.focused.tentacle_id}
              session={layout.focused}
              onRemoved={handleRemoved}
            />
          </div>
          <aside className="nm-tentacles-dashboard__side">
            {layout.rest.length > 0 ? (
              <ul className="nm-tentacles-dashboard__rest">
                {layout.rest.map((session) => (
                  <li key={session.tentacle_id}>
                    <RestItem
                      session={session}
                      onFocus={() => setFocusedId(session.tentacle_id)}
                    />
                  </li>
                ))}
              </ul>
            ) : null}
            <DashboardMiniGraph />
          </aside>
        </div>
      ) : null}
    </section>
  )
}

type RestItemProps = {
  session: TentacleSession
  onFocus: () => void
}

function RestItem({ session, onFocus }: RestItemProps) {
  const title = session.title || session.tentacle_id
  return (
    <article className="nm-tentacles-dashboard__rest-item">
      <div className="nm-tentacles-dashboard__rest-head">
        <h3>{title}</h3>
        <AgentStateBadge tentacleId={session.tentacle_id} fallback={session.alive ? "processing" : "idle"} />
      </div>
      <div className="nm-tentacles-dashboard__rest-actions">
        <button type="button" className="nm-button nm-button--ghost" onClick={onFocus}>
          Focar
        </button>
        {session.slug ? (
          <Link className="nm-tentacles-dashboard__rest-link" to={`/notes/${session.slug}/tentacle`}>
            abrir
          </Link>
        ) : null}
      </div>
    </article>
  )
}

function DashboardMiniGraph() {
  const state = useGraphData()

  if (state.status !== "ready") return null
  const agents = agentNoteIds(state.dataset.tags, state.dataset.noteTags)

  return (
    <div className="nm-tentacles-dashboard__minigraph" aria-label="Grafo dos agentes">
      <div className="nm-tentacles-dashboard__minigraph-header">
        <span>Grafo</span>
        <span className="nm-tentacles-dashboard__minigraph-count">{agents.size} agentes</span>
      </div>
      <div className="nm-tentacles-dashboard__minigraph-canvas">
        <GraphCanvas nodes={state.nodes} edges={state.edges} agentNoteIds={agents} />
      </div>
    </div>
  )
}
