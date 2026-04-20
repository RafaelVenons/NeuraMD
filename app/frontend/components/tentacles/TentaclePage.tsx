import { useCallback, useEffect, useRef, useState } from "react"
import { useParams } from "react-router-dom"
import { FitAddon } from "@xterm/addon-fit"
import { Terminal } from "@xterm/xterm"
import "@xterm/xterm/css/xterm.css"

import type { TentacleCableMessage, TentacleSession } from "~/components/tentacles/types"
import { getCableConsumer } from "~/runtime/cable"
import { fetchJson } from "~/runtime/fetchJson"

type LifecycleState =
  | { kind: "loading" }
  | { kind: "idle"; session: TentacleSession }
  | { kind: "running"; session: TentacleSession }
  | { kind: "error"; message: string }

type CableSubscription = {
  perform: (action: string, data: Record<string, unknown>) => void
  unsubscribe: () => void
}

const KNOWN_COMMANDS = ["bash", "claude"] as const

export function TentaclePage() {
  const { slug } = useParams<{ slug: string }>()
  const [state, setState] = useState<LifecycleState>({ kind: "loading" })
  const [command, setCommand] = useState<(typeof KNOWN_COMMANDS)[number]>("bash")
  const [status, setStatus] = useState("carregando…")
  const terminalHost = useRef<HTMLDivElement | null>(null)
  const terminalRef = useRef<Terminal | null>(null)
  const fitRef = useRef<FitAddon | null>(null)
  const subscriptionRef = useRef<CableSubscription | null>(null)
  const stateRef = useRef(state)
  stateRef.current = state

  useEffect(() => {
    if (!terminalHost.current) return
    const term = new Terminal({
      convertEol: true,
      cursorBlink: true,
      fontSize: 13,
      fontFamily: "JetBrains Mono, ui-monospace, monospace",
      theme: { background: "#0b0b0b" },
    })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(terminalHost.current)
    requestAnimationFrame(() => fit.fit())
    term.onData((data) => {
      subscriptionRef.current?.perform("input", { data })
    })
    terminalRef.current = term
    fitRef.current = fit

    const observer = new ResizeObserver(() => handleResize())
    observer.observe(terminalHost.current)

    return () => {
      observer.disconnect()
      subscriptionRef.current?.unsubscribe()
      subscriptionRef.current = null
      term.dispose()
      terminalRef.current = null
      fitRef.current = null
    }
  }, [])

  const subscribe = useCallback((tentacleId: string) => {
    if (subscriptionRef.current) return
    const consumer = getCableConsumer()
    const sub = consumer.subscriptions.create(
      { channel: "TentacleChannel", tentacle_id: tentacleId },
      {
        connected: () => handleResize(),
        received: (msg: TentacleCableMessage | null) => handleCable(msg),
      }
    )
    subscriptionRef.current = sub as unknown as CableSubscription
  }, [])

  const unsubscribe = useCallback(() => {
    subscriptionRef.current?.unsubscribe()
    subscriptionRef.current = null
  }, [])

  const handleResize = useCallback(() => {
    const term = terminalRef.current
    const fit = fitRef.current
    if (!term || !fit) return
    fit.fit()
    if (subscriptionRef.current) {
      subscriptionRef.current.perform("resize", { cols: term.cols, rows: term.rows })
    }
  }, [])

  const handleCable = useCallback((msg: TentacleCableMessage | null) => {
    const term = terminalRef.current
    if (!term || !msg) return
    if (msg.type === "output") {
      term.write(msg.data)
      return
    }
    if (msg.type === "exit") {
      const tail = msg.status == null ? "closed" : `exit ${msg.status}`
      term.writeln(`\r\n\x1b[90m[${tail}]\x1b[0m`)
      setStatus("encerrado")
      unsubscribe()
      const previous = stateRef.current
      if (previous.kind === "running") {
        setState({
          kind: "idle",
          session: { ...previous.session, alive: false, pid: null, started_at: null, command: null },
        })
      }
    }
  }, [unsubscribe])

  useEffect(() => {
    if (!slug) return
    let cancelled = false
    setState({ kind: "loading" })
    setStatus("carregando…")
    fetchJson<TentacleSession>(`/api/notes/${encodeURIComponent(slug)}/tentacle`)
      .then((session) => {
        if (cancelled) return
        if (session.alive) {
          terminalRef.current?.writeln(
            `\x1b[90m[tentacle ${session.tentacle_id} — reanexado${session.pid ? ` (pid ${session.pid})` : ""}]\x1b[0m`
          )
          subscribe(session.tentacle_id)
          setStatus("rodando")
          setState({ kind: "running", session })
        } else {
          setStatus("parado")
          setState({ kind: "idle", session })
        }
      })
      .catch((error: unknown) => {
        if (cancelled) return
        const message = error instanceof Error ? error.message : "Erro desconhecido"
        setStatus("erro")
        setState({ kind: "error", message })
      })
    return () => {
      cancelled = true
    }
  }, [slug, subscribe])

  const start = async () => {
    if (!slug) return
    setStatus("iniciando…")
    try {
      const session = await fetchJson<TentacleSession>(
        `/api/notes/${encodeURIComponent(slug)}/tentacle`,
        { method: "POST", body: { command } }
      )
      const pidSuffix = session.pid ? ` — pid ${session.pid}` : ""
      terminalRef.current?.writeln(
        `\x1b[90m[tentacle ${session.tentacle_id}${pidSuffix}]\x1b[0m`
      )
      subscribe(session.tentacle_id)
      setStatus("rodando")
      setState({ kind: "running", session })
    } catch (error) {
      const message = error instanceof Error ? error.message : "Erro ao iniciar"
      setStatus("erro")
      terminalRef.current?.writeln(`\x1b[31m[erro: ${message}]\x1b[0m`)
    }
  }

  const stop = async () => {
    if (!slug) return
    setStatus("parando…")
    try {
      await fetchJson(`/api/notes/${encodeURIComponent(slug)}/tentacle`, { method: "DELETE" })
    } catch (error) {
      terminalRef.current?.writeln(
        `\x1b[31m[erro ao parar: ${error instanceof Error ? error.message : "desconhecido"}]\x1b[0m`
      )
    } finally {
      unsubscribe()
      setStatus("parado")
      if (stateRef.current.kind === "running") {
        const previous = stateRef.current.session
        setState({
          kind: "idle",
          session: { ...previous, alive: false, pid: null, started_at: null, command: null },
        })
      }
    }
  }

  const isRunning = state.kind === "running"
  const disableControls = state.kind === "loading"

  return (
    <section className="nm-tentacle-page">
      <header className="nm-tentacle-page__header">
        <div>
          <h1>Tentáculo</h1>
          <p className="nm-tentacle-page__meta">
            Nota: <code>{slug}</code>
            {" · status: "}
            <span className="nm-tentacle-page__status">{status}</span>
            {isRunning && state.session.pid ? (
              <span className="nm-tentacle-page__muted"> — pid {state.session.pid}</span>
            ) : null}
          </p>
        </div>
        <div className="nm-tentacle-page__controls">
          <label>
            Comando
            <select
              value={command}
              onChange={(event) => setCommand(event.target.value as (typeof KNOWN_COMMANDS)[number])}
              disabled={isRunning || disableControls}
            >
              {KNOWN_COMMANDS.map((cmd) => (
                <option key={cmd} value={cmd}>
                  {cmd}
                </option>
              ))}
            </select>
          </label>
          {isRunning ? (
            <button type="button" className="nm-button nm-button--danger" onClick={stop}>
              Parar
            </button>
          ) : (
            <button type="button" className="nm-button" onClick={start} disabled={disableControls}>
              Iniciar
            </button>
          )}
        </div>
      </header>
      {state.kind === "error" ? (
        <p className="nm-tentacle-page__error">{state.message}</p>
      ) : null}
      <div className="nm-tentacle-page__terminal" ref={terminalHost} />
    </section>
  )
}
