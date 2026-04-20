import { useEffect, useState } from "react"
import { Link } from "react-router-dom"

import type { AiRequestDto, AiRequestsResponse } from "~/components/settings/types"
import { fetchJson } from "~/runtime/fetchJson"

export function AiOpsTab() {
  const [items, setItems] = useState<AiRequestDto[]>([])
  const [status, setStatus] = useState<"loading" | "idle" | "error">("loading")
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    fetchJson<AiRequestsResponse>("/api/ai_requests")
      .then((res) => {
        setItems(res.requests)
        setStatus("idle")
      })
      .catch((err: unknown) => {
        setStatus("error")
        setMessage(err instanceof Error ? err.message : "Erro ao carregar")
      })
  }, [])

  if (status === "loading") return <p className="nm-settings-placeholder">Carregando…</p>
  if (status === "error") return <p className="nm-settings-properties__error">{message}</p>

  return (
    <div className="nm-settings-list">
      <p className="nm-settings-list__hint">
        Últimas 50 chamadas. Gestão completa no dashboard legacy em <code>/ai/requests</code>.
      </p>
      {items.length === 0 ? (
        <p className="nm-settings-list__empty">Sem chamadas recentes.</p>
      ) : (
        <ul className="nm-settings-list__rows">
          {items.map((req) => (
            <li key={req.id} className="nm-settings-list__row">
              <div>
                <strong>{req.capability}</strong>
                <span className={`nm-settings-list__chip is-${req.status}`}>{req.status}</span>
                <span className="nm-settings-list__meta">{req.provider}</span>
              </div>
              <p className="nm-settings-list__meta">
                tentativa {req.attempts_count}/{req.max_attempts}
                {req.note ? (
                  <>
                    {" · "}
                    <Link to={`/notes/${req.note.slug}`}>{req.note.title}</Link>
                  </>
                ) : null}
              </p>
              {req.error_message ? (
                <p className="nm-settings-list__error">{req.error_message}</p>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
