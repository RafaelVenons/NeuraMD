import { useCallback, useEffect, useState } from "react"

import type { InboxMessage, InboxResponse } from "~/components/tentacles/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  slug: string
  refreshToken?: number
}

type Status = "idle" | "loading" | "error"

export function InboxPanel({ slug, refreshToken = 0 }: Props) {
  const [messages, setMessages] = useState<InboxMessage[]>([])
  const [pending, setPending] = useState(0)
  const [status, setStatus] = useState<Status>("loading")
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setStatus("loading")
    setMessage(null)
    try {
      const res = await fetchJson<InboxResponse>(
        `/api/notes/${encodeURIComponent(slug)}/tentacle/inbox`
      )
      setMessages(res.messages)
      setPending(res.pending_count)
      setStatus("idle")
    } catch (error) {
      setStatus("error")
      setMessage(error instanceof Error ? error.message : "Erro ao carregar")
    }
  }, [slug])

  useEffect(() => {
    void load()
  }, [load, refreshToken])

  const markDelivered = async () => {
    const ids = messages.filter((m) => !m.delivered).map((m) => m.id)
    if (ids.length === 0) return
    setBusy(true)
    setMessage(null)
    try {
      await fetchJson(
        `/api/notes/${encodeURIComponent(slug)}/tentacle/inbox/deliver`,
        { method: "POST", body: { ids } }
      )
      await load()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Erro ao marcar")
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="nm-tentacle-inbox">
      <header>
        <h3>Inbox</h3>
        <p className="nm-tentacle-inbox__meta">
          {status === "loading"
            ? "Carregando…"
            : `${messages.length} mensagem(ns) · ${pending} pendente(s)`}
        </p>
      </header>

      <div className="nm-tentacle-inbox__actions">
        <button
          type="button"
          className="nm-button"
          onClick={() => void load()}
          disabled={status === "loading"}
        >
          Atualizar
        </button>
        <button
          type="button"
          className="nm-button"
          onClick={() => void markDelivered()}
          disabled={busy || pending === 0}
        >
          Marcar visíveis como entregues
        </button>
      </div>

      {status === "error" && message ? (
        <p className="nm-tentacle-inbox__error">{message}</p>
      ) : null}

      <ul className="nm-tentacle-inbox__list">
        {messages.length === 0 && status === "idle" ? (
          <li className="nm-tentacle-inbox__empty">Sem mensagens ainda.</li>
        ) : null}
        {messages.map((m) => (
          <li key={m.id} className={m.delivered ? "is-delivered" : undefined}>
            <header>
              <span className="nm-tentacle-inbox__from">{m.from_title}</span>
              <time dateTime={m.created_at}>{formatDate(m.created_at)}</time>
            </header>
            <pre className="nm-tentacle-inbox__body">{m.content}</pre>
            {m.delivered ? (
              <span className="nm-tentacle-inbox__chip">entregue</span>
            ) : (
              <span className="nm-tentacle-inbox__chip nm-tentacle-inbox__chip--pending">pendente</span>
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
