import type { RuntimeState } from "~/runtime/runtimeStateMachine"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"

type SessionLike = { tentacle_id: string }

export type DashboardLayout<S extends SessionLike> = {
  focused: S | null
  rest: S[]
  needsAttention: S[]
}

const PRIORITY: Record<RuntimeState | "unknown", number> = {
  needs_input: 0,
  processing: 1,
  idle: 2,
  unknown: 3,
  exited: 4,
}

function stateFor(snapshot: RuntimeStateSnapshot, id: string): RuntimeState | "unknown" {
  return snapshot[id]?.state ?? "unknown"
}

export function selectDashboardLayout<S extends SessionLike>(input: {
  sessions: S[]
  focusedId: string | null
  runtimeStates: RuntimeStateSnapshot
}): DashboardLayout<S> {
  const { sessions, focusedId, runtimeStates } = input

  if (sessions.length === 0) {
    return { focused: null, rest: [], needsAttention: [] }
  }

  const needsAttention = sessions.filter(
    (session) => stateFor(runtimeStates, session.tentacle_id) === "needs_input"
  )

  const explicitlyFocused = focusedId
    ? sessions.find((s) => s.tentacle_id === focusedId) ?? null
    : null

  const focused = explicitlyFocused ?? needsAttention[0] ?? sessions[0]

  const rest = sessions
    .filter((session) => session.tentacle_id !== focused.tentacle_id)
    .slice()
    .sort((left, right) => {
      const leftPriority = PRIORITY[stateFor(runtimeStates, left.tentacle_id)]
      const rightPriority = PRIORITY[stateFor(runtimeStates, right.tentacle_id)]
      return leftPriority - rightPriority
    })

  return { focused, rest, needsAttention }
}
