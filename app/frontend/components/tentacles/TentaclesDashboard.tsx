import { useCallback, useEffect, useState } from "react"

import { TentacleMiniPanel } from "~/components/tentacles/TentacleMiniPanel"
import type { TentacleSession, TentacleSessionsIndex } from "~/components/tentacles/types"
import { fetchJson } from "~/runtime/fetchJson"

type Status = "loading" | "idle" | "error"

export function TentaclesDashboard() {
  const [sessions, setSessions] = useState<TentacleSession[]>([])
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)

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
  }, [])

  return (
    <section className="nm-tentacles-dashboard">
      <header className="nm-tentacles-dashboard__header">
        <div>
          <h1>Tentáculos ativos</h1>
          <p className="nm-tentacles-dashboard__meta">
            {status === "loading"
              ? "Carregando…"
              : `${sessions.length} sessão(ões) vivas`}
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

      <div className="nm-tentacles-dashboard__grid">
        {sessions.map((session) => (
          <TentacleMiniPanel
            key={session.tentacle_id}
            session={session}
            onRemoved={handleRemoved}
          />
        ))}
      </div>
    </section>
  )
}
