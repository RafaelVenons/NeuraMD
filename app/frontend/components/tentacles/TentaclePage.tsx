import { useCallback, useEffect, useRef, useState } from "react"
import { useLocation, useNavigate, useParams } from "react-router-dom"
import { FitAddon } from "@xterm/addon-fit"
import { Terminal } from "@xterm/xterm"
import "@xterm/xterm/css/xterm.css"

import { ContextLinks } from "~/components/tentacles/ContextLinks"
import { InboxPanel } from "~/components/tentacles/InboxPanel"
import { keyEventToInputBytes } from "~/components/tentacles/keyEvents"
import { createResizeScheduler, type ResizeScheduler } from "~/components/tentacles/resizeScheduler"
import { RouteSuggestionCard } from "~/components/tentacles/RouteSuggestionCard"
import { SpawnChildForm } from "~/components/tentacles/SpawnChildForm"
import type {
  RouteSuggestion,
  TentacleCableMessage,
  TentacleSession,
} from "~/components/tentacles/types"
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

type PendingPrompt = { slug: string; prompt: string }

export function TentaclePage() {
  const { slug } = useParams<{ slug: string }>()
  const location = useLocation()
  const navigate = useNavigate()
  const initialRouted = (location.state as { initialPrompt?: string } | null)?.initialPrompt
  const pendingInitialPromptRef = useRef<PendingPrompt | null>(
    slug && initialRouted != null && initialRouted !== ""
      ? { slug, prompt: initialRouted }
      : null
  )
  const [state, setState] = useState<LifecycleState>({ kind: "loading" })
  const [command, setCommand] = useState<(typeof KNOWN_COMMANDS)[number]>("bash")
  const [status, setStatus] = useState("carregando…")
  const [suggestions, setSuggestions] = useState<RouteSuggestion[]>([])
  const terminalHost = useRef<HTMLDivElement | null>(null)
  const terminalRef = useRef<Terminal | null>(null)
  const fitRef = useRef<FitAddon | null>(null)
  const schedulerRef = useRef<ResizeScheduler | null>(null)
  const subscriptionRef = useRef<CableSubscription | null>(null)
  const subscribedTentacleIdRef = useRef<string | null>(null)
  const routedDeliveryRef = useRef<string | null>(null)
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
    term.onData((data) => {
      subscriptionRef.current?.perform("input", { data })
    })
    term.attachCustomKeyEventHandler((event) => {
      if (event.type !== "keydown") return true
      const bytes = keyEventToInputBytes(event)
      if (bytes === null) return true
      subscriptionRef.current?.perform("input", { data: bytes })
      return false
    })
    terminalRef.current = term
    fitRef.current = fit

    const scheduler = createResizeScheduler({
      onFit: () => {
        fit.fit()
        subscriptionRef.current?.perform("resize", { cols: term.cols, rows: term.rows })
      },
      debounceMs: 150,
    })
    schedulerRef.current = scheduler
    requestAnimationFrame(() => scheduler.flush())

    const observer = new ResizeObserver(() => scheduler.schedule())
    observer.observe(terminalHost.current)

    const onVisibility = () => {
      if (document.visibilityState !== "visible") return
      scheduler.flush()
      term.refresh(0, Math.max(term.rows - 1, 0))
    }
    document.addEventListener("visibilitychange", onVisibility)

    return () => {
      document.removeEventListener("visibilitychange", onVisibility)
      observer.disconnect()
      scheduler.dispose()
      schedulerRef.current = null
      subscriptionRef.current?.unsubscribe()
      subscriptionRef.current = null
      term.dispose()
      terminalRef.current = null
      fitRef.current = null
    }
  }, [])

  const subscribe = useCallback((tentacleId: string) => {
    if (
      subscriptionRef.current &&
      subscribedTentacleIdRef.current === tentacleId
    ) {
      return
    }
    subscriptionRef.current?.unsubscribe()
    subscriptionRef.current = null
    subscribedTentacleIdRef.current = tentacleId

    const consumer = getCableConsumer()
    const sub = consumer.subscriptions.create(
      { channel: "TentacleChannel", tentacle_id: tentacleId },
      {
        connected: () => {
          queueMicrotask(() => {
            if (subscribedTentacleIdRef.current !== tentacleId) return
            if (!subscriptionRef.current) return
            schedulerRef.current?.flush()
            const term = terminalRef.current
            if (term) term.refresh(0, Math.max(term.rows - 1, 0))
          })
        },
        received: (msg: TentacleCableMessage | null) => handleCable(msg),
      }
    )
    subscriptionRef.current = sub as unknown as CableSubscription
  }, [])

  const unsubscribe = useCallback(() => {
    subscriptionRef.current?.unsubscribe()
    subscriptionRef.current = null
    subscribedTentacleIdRef.current = null
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
      return
    }
    if (msg.type === "context-warning") {
      const pct = Math.round(msg.ratio * 100)
      term.writeln(
        `\r\n\x1b[33m[context-warning ${pct}% — ~${msg.estimated_tokens} tokens]\x1b[0m`
      )
      return
    }
    if (msg.type === "route-suggestion") {
      const entry: RouteSuggestion = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        target: msg.target,
        suggested_prompt: msg.suggested_prompt,
        rationale: msg.rationale,
      }
      setSuggestions((prev) => [...prev, entry])
      term.writeln(
        `\r\n\x1b[36m[encaminhamento → ${msg.target.title}]\x1b[0m`
      )
    }
  }, [unsubscribe])

  const dismissSuggestion = useCallback((id: string) => {
    setSuggestions((prev) => prev.filter((s) => s.id !== id))
  }, [])

  const clearLocationState = useCallback(
    (forSlug: string) => {
      navigate(`/notes/${encodeURIComponent(forSlug)}/tentacle`, {
        replace: true,
        state: null,
      })
    },
    [navigate]
  )

  const startSession = useCallback(
    async (cmd: (typeof KNOWN_COMMANDS)[number], initialPrompt?: string) => {
      if (!slug) return
      setStatus("iniciando…")
      try {
        const body: Record<string, unknown> = { command: cmd }
        if (initialPrompt) body.initial_prompt = initialPrompt
        const session = await fetchJson<TentacleSession>(
          `/api/notes/${encodeURIComponent(slug)}/tentacle`,
          { method: "POST", body }
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
    },
    [slug, subscribe]
  )

  const deliverRoutedPromptToAlive = useCallback(
    async (targetSlug: string, prompt: string) => {
      try {
        await fetchJson<TentacleSession>(
          `/api/notes/${encodeURIComponent(targetSlug)}/tentacle`,
          { method: "POST", body: { command: "claude", initial_prompt: prompt } }
        )
      } catch (error) {
        terminalRef.current?.writeln(
          `\x1b[31m[erro ao entregar prompt: ${error instanceof Error ? error.message : "desconhecido"}]\x1b[0m`
        )
      }
    },
    []
  )

  useEffect(() => {
    if (!slug) return
    const routed = (location.state as { initialPrompt?: string } | null)?.initialPrompt
    if (routed == null || routed === "") return
    pendingInitialPromptRef.current = { slug, prompt: routed }
    const current = stateRef.current
    if (current.kind !== "running") return
    if (subscribedTentacleIdRef.current !== current.session.tentacle_id) return
    if (routedDeliveryRef.current === `${slug}:${routed}`) return
    routedDeliveryRef.current = `${slug}:${routed}`
    pendingInitialPromptRef.current = null
    clearLocationState(slug)
    void deliverRoutedPromptToAlive(slug, routed)
  }, [location.state, slug, clearLocationState, deliverRoutedPromptToAlive])

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
          const pending = pendingInitialPromptRef.current
          if (pending && pending.slug === slug) {
            const key = `${slug}:${pending.prompt}`
            if (routedDeliveryRef.current !== key) {
              routedDeliveryRef.current = key
              const prompt = pending.prompt
              pendingInitialPromptRef.current = null
              clearLocationState(slug)
              void deliverRoutedPromptToAlive(slug, prompt)
            }
          }
        } else if (pendingInitialPromptRef.current?.slug === slug) {
          const pending = pendingInitialPromptRef.current
          const key = `${slug}:${pending.prompt}`
          if (routedDeliveryRef.current === key) {
            setState({ kind: "idle", session })
          } else {
            routedDeliveryRef.current = key
            const prompt = pending.prompt
            pendingInitialPromptRef.current = null
            clearLocationState(slug)
            setCommand("claude")
            setState({ kind: "idle", session })
            void startSession("claude", prompt)
          }
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
      subscriptionRef.current?.unsubscribe()
      subscriptionRef.current = null
      subscribedTentacleIdRef.current = null
    }
  }, [slug, subscribe, startSession, clearLocationState, deliverRoutedPromptToAlive])

  const start = () => startSession(command)

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
      <div className="nm-tentacle-page__body">
        <div className="nm-tentacle-page__terminal" ref={terminalHost} />
        <aside className="nm-tentacle-page__side">
          {suggestions.map((s) => (
            <RouteSuggestionCard key={s.id} suggestion={s} onDismiss={dismissSuggestion} />
          ))}
          {slug ? (
            <>
              <InboxPanel slug={slug} />
              <SpawnChildForm parentSlug={slug} />
              <ContextLinks slug={slug} />
            </>
          ) : null}
        </aside>
      </div>
    </section>
  )
}
