import { useSyncExternalStore } from "react"

import type { RuntimeState } from "~/runtime/runtimeStateMachine"
import { runtimeStateStore } from "~/runtime/runtimeStateStore"

const LABEL: Record<RuntimeState, string> = {
  idle: "ocioso",
  processing: "processando…",
  needs_input: "aguardando você",
  exited: "encerrado",
}

type Props = {
  tentacleId: string | null | undefined
  fallback?: RuntimeState
}

export function AgentStateBadge({ tentacleId, fallback = "idle" }: Props) {
  const snapshot = useSyncExternalStore(
    runtimeStateStore.subscribe,
    runtimeStateStore.getSnapshot,
    runtimeStateStore.getSnapshot
  )
  const entry = tentacleId ? snapshot[tentacleId] : undefined
  const state: RuntimeState = entry?.state ?? fallback

  return (
    <span
      className={`nm-agent-state-badge nm-agent-state-badge--${state}`}
      role="status"
      aria-live={state === "needs_input" ? "polite" : "off"}
      data-state={state}
    >
      <span className="nm-agent-state-badge__dot" aria-hidden />
      <span className="nm-agent-state-badge__label">{LABEL[state]}</span>
    </span>
  )
}
