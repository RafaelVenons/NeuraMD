import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react"

import { selectTilingLayout, type TilingSlot } from "~/components/tentacles/tilingLayout"
import { StatusCard } from "~/components/tentacles/StatusCard"
import { TilingTile } from "~/components/tentacles/TilingTile"
import { useTilingShortcuts } from "~/components/tentacles/tilingShortcuts"
import type { TentacleSession, TentacleSessionsIndex } from "~/components/tentacles/types"
import { useViewport } from "~/components/tentacles/useViewport"
import { GraphCanvas } from "~/components/graph/GraphCanvas"
import { agentNoteIds } from "~/components/graph/graphFilters"
import { useGraphData } from "~/components/graph/useGraphData"
import { fetchJson } from "~/runtime/fetchJson"
import { runtimeStateStore } from "~/runtime/runtimeStateStore"

type Status = "loading" | "idle" | "error"

function slotStyle(slot: TilingSlot): React.CSSProperties {
  return {
    gridColumn: `${slot.col} / span ${slot.colSpan}`,
    gridRow: `${slot.row} / span ${slot.rowSpan}`,
  }
}

export function TentaclesDashboard() {
  const [sessions, setSessions] = useState<TentacleSession[]>([])
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)
  const [focusedId, setFocusedId] = useState<string | null>(null)
  const [soloId, setSoloId] = useState<string | null>(null)
  const viewport = useViewport()

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
    setSoloId((current) => (current === tentacleId ? null : current))
    runtimeStateStore.remove(tentacleId)
  }, [])

  useEffect(() => {
    if (!soloId) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setSoloId(null)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [soloId])

  const effectiveSessions = useMemo(() => {
    if (!soloId) return sessions
    const match = sessions.filter((s) => s.tentacle_id === soloId)
    return match.length > 0 ? match : sessions
  }, [sessions, soloId])

  const layout = useMemo(
    () => selectTilingLayout({ sessions: effectiveSessions, focusedId, runtimeStates, viewport }),
    [effectiveSessions, focusedId, runtimeStates, viewport]
  )

  const handleFocus = useCallback((tentacleId: string) => {
    setFocusedId(tentacleId)
  }, [])

  const handleSolo = useCallback((tentacleId: string) => {
    setSoloId((current) => (current === tentacleId ? null : tentacleId))
  }, [])

  const handlePromote = useCallback((tentacleId: string) => {
    setFocusedId(tentacleId)
  }, [])

  const handleSoloToggle = useCallback(() => {
    setSoloId((current) => {
      if (current) return null
      return focusedId ?? null
    })
  }, [focusedId])

  const graphRef = useRef<HTMLElement | null>(null)
  const handleFocusGraph = useCallback(() => {
    graphRef.current?.focus()
  }, [])

  const tileIds = useMemo(() => layout.tiles.map((t) => t.session.tentacle_id), [layout.tiles])

  useTilingShortcuts({
    tileIds,
    focusedId,
    onFocusId: handleFocus,
    onSoloToggle: handleSoloToggle,
    onFocusGraph: handleFocusGraph,
  })

  const aliveCount = sessions.filter((s) => s.alive).length
  const needsInputCount = sessions.filter(
    (s) => runtimeStates[s.tentacle_id]?.state === "needs_input"
  ).length
  const hasContent = layout.tiles.length > 0 || layout.cards.length > 0

  return (
    <section className="nm-tentacles-dashboard">
      <header className="nm-tentacles-dashboard__header">
        <div>
          <h1>Tentáculos ativos</h1>
          <p className="nm-tentacles-dashboard__meta">
            {status === "loading"
              ? "Carregando…"
              : `${aliveCount} sessão(ões) vivas${
                  needsInputCount > 0 ? ` · ${needsInputCount} aguardando você` : ""
                }${soloId ? " · solo (Esc)" : ""}`}
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

      {status === "idle" && aliveCount === 0 ? (
        <p className="nm-tentacles-dashboard__empty">
          Nenhum tentáculo vivo. Abra uma nota e inicie um em <code>/app/notes/:slug/tentacle</code>.
        </p>
      ) : null}

      {hasContent ? (
        <div
          className="nm-tiling"
          style={{
            gridTemplateColumns: layout.columns.map((c) => `${c}fr`).join(" "),
            gridTemplateRows: layout.rows.map((r) => `${r}fr`).join(" "),
          }}
        >
          {layout.tiles.map((tile) => (
            <TilingTile
              key={tile.session.tentacle_id}
              tile={tile}
              isFocused={focusedId === tile.session.tentacle_id}
              onFocus={handleFocus}
              onSolo={handleSolo}
              onRemoved={handleRemoved}
            />
          ))}
          {layout.cards.length > 0 ? (
            <div
              className="nm-tiling__cards-row"
              style={{ gridColumn: "1 / -1", gridRow: `${layout.rows.length} / span 1` }}
            >
              {layout.cards.map((card) => (
                <StatusCard
                  key={card.session.tentacle_id}
                  card={card}
                  onPromote={handlePromote}
                />
              ))}
            </div>
          ) : null}
          {layout.miniGraphSlot ? (
            <div className="nm-tiling__minigraph-slot" style={slotStyle(layout.miniGraphSlot)}>
              <DashboardMiniGraph forwardedRef={graphRef} />
            </div>
          ) : null}
        </div>
      ) : null}

      {hasContent && !layout.miniGraphSlot ? (
        <aside className="nm-tentacles-dashboard__minigraph-drawer">
          <DashboardMiniGraph forwardedRef={graphRef} />
        </aside>
      ) : null}

      {layout.hasMore ? (
        <p className="nm-tiling__more">
          {sessions.length - 16} sessão(ões) extras não exibidas — paginação em breve.
        </p>
      ) : null}
    </section>
  )
}

type MiniGraphProps = {
  forwardedRef?: React.RefObject<HTMLElement | null>
}

function DashboardMiniGraph({ forwardedRef }: MiniGraphProps) {
  const state = useGraphData()

  if (state.status !== "ready") return null
  const agents = agentNoteIds(state.dataset.tags, state.dataset.noteTags)

  return (
    <section
      ref={forwardedRef as React.RefObject<HTMLElement> | undefined}
      className="nm-tentacles-dashboard__minigraph"
      aria-label="Grafo dos agentes"
      tabIndex={-1}
    >
      <div className="nm-tentacles-dashboard__minigraph-header">
        <span>Grafo</span>
        <span className="nm-tentacles-dashboard__minigraph-count">{agents.size} agentes</span>
      </div>
      <div className="nm-tentacles-dashboard__minigraph-canvas">
        <GraphCanvas nodes={state.nodes} edges={state.edges} agentNoteIds={agents} />
      </div>
    </section>
  )
}
