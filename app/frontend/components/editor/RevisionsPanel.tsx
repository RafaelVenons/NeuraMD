import { useCallback, useEffect, useState } from "react"

import { fetchJson } from "~/runtime/fetchJson"

type Revision = {
  id: string
  created_at: string
  ai_generated: boolean
  is_head: boolean
}

type Props = {
  slug: string
  onRestored: () => void
  refreshToken: number
}

type Status = "idle" | "loading" | "error"

export function RevisionsPanel({ slug, onRestored, refreshToken }: Props) {
  const [revisions, setRevisions] = useState<Revision[]>([])
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)
  const [restoring, setRestoring] = useState<string | null>(null)

  const load = useCallback(async () => {
    setStatus("loading")
    try {
      const res = await fetchJson<{ revisions: Revision[] }>(
        `/api/notes/${encodeURIComponent(slug)}/revisions`
      )
      setRevisions(res.revisions)
      setStatus("idle")
      setMessage(null)
    } catch (error) {
      setStatus("error")
      setMessage(error instanceof Error ? error.message : "Erro ao carregar")
    }
  }, [slug])

  useEffect(() => {
    void load()
  }, [load, refreshToken])

  const restore = async (rev: Revision) => {
    if (!window.confirm(`Restaurar revisão de ${formatDate(rev.created_at)}? Uma nova revisão será criada.`)) {
      return
    }
    setRestoring(rev.id)
    setMessage(null)
    try {
      await fetchJson(
        `/api/notes/${encodeURIComponent(slug)}/revisions/${rev.id}/restore`,
        { method: "POST", body: {} }
      )
      setRestoring(null)
      onRestored()
    } catch (error) {
      setRestoring(null)
      setMessage(error instanceof Error ? error.message : "Erro ao restaurar")
    }
  }

  return (
    <section className="nm-revisions-panel">
      <header>
        <h3>Revisões</h3>
        <p className="nm-editor-page__muted">
          {status === "loading" ? "Carregando…" : `${revisions.length} checkpoint(s)`}
        </p>
      </header>
      {status === "error" && message ? (
        <p className="nm-revisions-panel__error">{message}</p>
      ) : null}
      {revisions.length === 0 && status === "idle" ? (
        <p className="nm-editor-page__muted">Sem checkpoints ainda.</p>
      ) : null}
      <ul className="nm-revisions-panel__list">
        {revisions.map((rev) => (
          <li key={rev.id} className={rev.is_head ? "is-head" : undefined}>
            <div className="nm-revisions-panel__meta">
              <span className="nm-revisions-panel__date">{formatDate(rev.created_at)}</span>
              <span className="nm-revisions-panel__tags">
                {rev.is_head ? <span className="nm-revisions-panel__chip">HEAD</span> : null}
                {rev.ai_generated ? <span className="nm-revisions-panel__chip">AI</span> : null}
              </span>
            </div>
            {rev.is_head ? null : (
              <button
                type="button"
                className="nm-revisions-panel__restore"
                onClick={() => restore(rev)}
                disabled={restoring === rev.id}
              >
                {restoring === rev.id ? "Restaurando…" : "Restaurar"}
              </button>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}
