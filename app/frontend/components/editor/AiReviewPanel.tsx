import { useCallback, useEffect, useState } from "react"

import { fetchJson } from "~/runtime/fetchJson"

type AiRequestSummary = {
  id: string
  capability: string
  provider: string
  status: string
  attempts_count: number
  max_attempts: number
  last_error_kind: string | null
  error_message: string | null
  created_at: string
}

type Response = { requests: AiRequestSummary[] }

type Props = {
  slug: string
}

export function AiReviewPanel({ slug }: Props) {
  const [items, setItems] = useState<AiRequestSummary[]>([])
  const [status, setStatus] = useState<"loading" | "idle" | "error">("loading")
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setStatus("loading")
    setMessage(null)
    try {
      const res = await fetchJson<Response>(`/api/notes/${encodeURIComponent(slug)}/ai_requests`)
      setItems(res.requests)
      setStatus("idle")
    } catch (err) {
      setStatus("error")
      setMessage(err instanceof Error ? err.message : "Erro ao carregar")
    }
  }, [slug])

  useEffect(() => {
    void load()
  }, [load])

  return (
    <section className="nm-ai-panel">
      <header className="nm-ai-panel__header">
        <h3>IA — últimas requisições</h3>
        <button type="button" className="nm-ai-panel__refresh" onClick={() => void load()} disabled={status === "loading"}>
          ↻
        </button>
      </header>
      <p className="nm-ai-panel__hint">
        Para enfileirar uma revisão, use a UI legacy em <code>/notes/{slug}</code>. O enqueue em
        React chega na próxima fase.
      </p>
      {status === "loading" ? (
        <p className="nm-ai-panel__meta">Carregando…</p>
      ) : status === "error" ? (
        <p className="nm-ai-panel__error">{message}</p>
      ) : items.length === 0 ? (
        <p className="nm-ai-panel__meta">Nenhuma chamada nesta nota.</p>
      ) : (
        <ul className="nm-ai-panel__list">
          {items.map((req) => (
            <li key={req.id} className="nm-ai-panel__item">
              <div>
                <strong>{req.capability}</strong>
                <span className={`nm-ai-panel__chip is-${req.status}`}>{req.status}</span>
                <span className="nm-ai-panel__meta"> · {req.provider}</span>
              </div>
              <p className="nm-ai-panel__meta">
                tentativa {req.attempts_count}/{req.max_attempts} · {new Date(req.created_at).toLocaleString()}
              </p>
              {req.error_message ? (
                <p className="nm-ai-panel__error-line">{req.error_message}</p>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
