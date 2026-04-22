import type { RuntimeState } from "~/runtime/runtimeStateMachine"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"

export type SessionTabState = RuntimeState | "unknown"

export type SessionTab = {
  id: string
  slug: string | null
  label: string
  state: SessionTabState
  needsAttention: boolean
}

type SessionLike = {
  tentacle_id: string
  slug?: string
  title?: string
  alive: boolean
  started_at?: string | null
}

const PRIORITY: Record<SessionTabState, number> = {
  needs_input: 0,
  processing: 1,
  idle: 2,
  unknown: 3,
  exited: 4,
}

const DEFAULT_MAX_LABEL = 24

function truncate(value: string, max: number): string {
  if (value.length <= max) return value
  if (max <= 1) return "…"
  return `${value.slice(0, max - 1)}…`
}

function labelFor(session: SessionLike, max: number): string {
  const base = session.title && session.title.length > 0 ? session.title : session.tentacle_id
  return truncate(base, max)
}

function stateFor(snapshot: RuntimeStateSnapshot, id: string): SessionTabState {
  return snapshot[id]?.state ?? "unknown"
}

function compareStartedAt(left: string | null, right: string | null): number {
  if (left === null && right === null) return 0
  if (left === null) return 1
  if (right === null) return -1
  return left < right ? -1 : left > right ? 1 : 0
}

export function deriveSessionTabs(input: {
  sessions: SessionLike[]
  runtimeStates: RuntimeStateSnapshot
  maxLabelLength?: number
}): SessionTab[] {
  const { sessions, runtimeStates } = input
  const maxLabelLength = input.maxLabelLength ?? DEFAULT_MAX_LABEL

  const alive = sessions.filter((session) => session.alive)
  const startedAt = new Map<string, string | null>(
    alive.map((session) => [session.tentacle_id, session.started_at ?? null])
  )

  const tabs: SessionTab[] = alive.map((session) => {
    const state = stateFor(runtimeStates, session.tentacle_id)
    return {
      id: session.tentacle_id,
      slug: session.slug ?? null,
      label: labelFor(session, maxLabelLength),
      state,
      needsAttention: state === "needs_input",
    }
  })

  tabs.sort((left, right) => {
    const priorityDiff = PRIORITY[left.state] - PRIORITY[right.state]
    if (priorityDiff !== 0) return priorityDiff
    return compareStartedAt(startedAt.get(left.id) ?? null, startedAt.get(right.id) ?? null)
  })

  return tabs
}
