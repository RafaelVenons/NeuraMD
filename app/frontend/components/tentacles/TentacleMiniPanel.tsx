import { useCallback, useEffect, useRef, useState } from "react"
import { Link } from "react-router-dom"
import { FitAddon } from "@xterm/addon-fit"
import { Terminal } from "@xterm/xterm"
import "@xterm/xterm/css/xterm.css"

import type { TentacleCableMessage, TentacleSession } from "~/components/tentacles/types"
import { getCableConsumer } from "~/runtime/cable"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  session: TentacleSession
  onRemoved: (tentacleId: string) => void
}

type CableSubscription = {
  perform: (action: string, data: Record<string, unknown>) => void
  unsubscribe: () => void
}

export function TentacleMiniPanel({ session, onRemoved }: Props) {
  const [alive, setAlive] = useState(session.alive)
  const [status, setStatus] = useState(session.alive ? "rodando" : "parado")
  const host = useRef<HTMLDivElement | null>(null)
  const termRef = useRef<Terminal | null>(null)
  const fitRef = useRef<FitAddon | null>(null)
  const subRef = useRef<CableSubscription | null>(null)

  useEffect(() => {
    if (!host.current) return
    const term = new Terminal({
      convertEol: true,
      cursorBlink: true,
      fontSize: 12,
      fontFamily: "JetBrains Mono, ui-monospace, monospace",
      theme: { background: "#0b0b0b" },
    })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(host.current)
    requestAnimationFrame(() => fit.fit())
    term.onData((data) => subRef.current?.perform("input", { data }))
    termRef.current = term
    fitRef.current = fit

    const observer = new ResizeObserver(() => handleResize())
    observer.observe(host.current)

    if (session.alive) {
      term.writeln(
        `\x1b[90m[tentacle ${session.tentacle_id} — reanexado${session.pid ? ` (pid ${session.pid})` : ""}]\x1b[0m`
      )
      subscribe()
    }

    return () => {
      observer.disconnect()
      subRef.current?.unsubscribe()
      subRef.current = null
      term.dispose()
      termRef.current = null
      fitRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session.tentacle_id])

  const subscribe = useCallback(() => {
    if (subRef.current) return
    const consumer = getCableConsumer()
    const sub = consumer.subscriptions.create(
      { channel: "TentacleChannel", tentacle_id: session.tentacle_id },
      {
        connected: () => handleResize(),
        received: (msg: TentacleCableMessage | null) => handleCable(msg),
      }
    )
    subRef.current = sub as unknown as CableSubscription
  }, [session.tentacle_id])

  const handleResize = useCallback(() => {
    const term = termRef.current
    const fit = fitRef.current
    if (!term || !fit) return
    fit.fit()
    subRef.current?.perform("resize", { cols: term.cols, rows: term.rows })
  }, [])

  const handleCable = useCallback(
    (msg: TentacleCableMessage | null) => {
      const term = termRef.current
      if (!term || !msg) return
      if (msg.type === "output") {
        term.write(msg.data)
        return
      }
      if (msg.type === "exit") {
        const tail = msg.status == null ? "closed" : `exit ${msg.status}`
        term.writeln(`\r\n\x1b[90m[${tail}]\x1b[0m`)
        setAlive(false)
        setStatus("encerrado")
        subRef.current?.unsubscribe()
        subRef.current = null
      }
    },
    []
  )

  const stop = async () => {
    if (!session.slug) return
    setStatus("parando…")
    try {
      await fetchJson(`/api/notes/${encodeURIComponent(session.slug)}/tentacle`, {
        method: "DELETE",
      })
    } catch (err) {
      termRef.current?.writeln(
        `\x1b[31m[erro ao parar: ${err instanceof Error ? err.message : "desconhecido"}]\x1b[0m`
      )
    } finally {
      subRef.current?.unsubscribe()
      subRef.current = null
      setAlive(false)
      setStatus("parado")
      onRemoved(session.tentacle_id)
    }
  }

  const titleDisplay = session.title || session.tentacle_id

  return (
    <article className="nm-tentacle-mini">
      <header>
        <div className="nm-tentacle-mini__head">
          <h3>{titleDisplay}</h3>
          <p className="nm-tentacle-mini__meta">
            <span className={alive ? "nm-tentacle-mini__dot is-alive" : "nm-tentacle-mini__dot"} />
            {status}
            {session.pid ? <span className="nm-tentacle-mini__muted"> · pid {session.pid}</span> : null}
          </p>
        </div>
        <div className="nm-tentacle-mini__actions">
          {session.slug ? (
            <Link className="nm-tentacle-mini__link" to={`/notes/${session.slug}/tentacle`}>
              abrir
            </Link>
          ) : null}
          {alive ? (
            <button type="button" className="nm-button nm-button--danger" onClick={stop}>
              Parar
            </button>
          ) : null}
        </div>
      </header>
      <div className="nm-tentacle-mini__terminal" ref={host} />
    </article>
  )
}
