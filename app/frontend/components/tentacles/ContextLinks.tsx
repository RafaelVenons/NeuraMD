import { useEffect, useState } from "react"
import { Link } from "react-router-dom"

import type { NoteLinkRef, NoteLinksResponse } from "~/components/tentacles/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  slug: string
}

type Status = "loading" | "idle" | "error"

export function ContextLinks({ slug }: Props) {
  const [outgoing, setOutgoing] = useState<NoteLinkRef[]>([])
  const [incoming, setIncoming] = useState<NoteLinkRef[]>([])
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setStatus("loading")
    fetchJson<NoteLinksResponse>(`/api/notes/${encodeURIComponent(slug)}/links`)
      .then((res) => {
        if (cancelled) return
        setOutgoing(res.outgoing)
        setIncoming(res.incoming)
        setStatus("idle")
      })
      .catch((err: unknown) => {
        if (cancelled) return
        setStatus("error")
        setMessage(err instanceof Error ? err.message : "Erro ao carregar")
      })
    return () => {
      cancelled = true
    }
  }, [slug])

  return (
    <section className="nm-tentacle-links">
      <header>
        <h3>Contexto</h3>
      </header>
      {status === "error" && message ? (
        <p className="nm-tentacle-links__error">{message}</p>
      ) : null}
      <div className="nm-tentacle-links__group">
        <h4>Aponta para</h4>
        {renderList(outgoing, status)}
      </div>
      <div className="nm-tentacle-links__group">
        <h4>Apontado por</h4>
        {renderList(incoming, status)}
      </div>
    </section>
  )
}

function renderList(items: NoteLinkRef[], status: Status) {
  if (status === "loading") return <p className="nm-tentacle-links__muted">Carregando…</p>
  if (items.length === 0) return <p className="nm-tentacle-links__muted">—</p>
  return (
    <ul>
      {items.map((item) => (
        <li key={`${item.id}-${item.hier_role ?? "none"}`}>
          <Link to={`/notes/${item.slug}`}>{item.title}</Link>
          {item.hier_role ? (
            <span className="nm-tentacle-links__role"> · {item.hier_role}</span>
          ) : null}
        </li>
      ))}
    </ul>
  )
}
