import type { RuntimeState } from "~/runtime/runtimeStateMachine"

export type RuntimeStateEntry = {
  state: RuntimeState
  at: number
}

export type RuntimeStateSnapshot = Record<string, RuntimeStateEntry>

export type RuntimeStateStore = {
  getSnapshot: () => RuntimeStateSnapshot
  subscribe: (listener: () => void) => () => void
  setState: (id: string, state: RuntimeState, now?: number) => void
  remove: (id: string) => void
}

export function createRuntimeStateStore(): RuntimeStateStore {
  let snapshot: RuntimeStateSnapshot = {}
  const listeners = new Set<() => void>()

  const emit = () => {
    for (const listener of listeners) listener()
  }

  return {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
    setState(id, state, now) {
      const existing = snapshot[id]
      if (existing && existing.state === state) return
      const at = now ?? Date.now()
      snapshot = { ...snapshot, [id]: { state, at } }
      emit()
    },
    remove(id) {
      if (!(id in snapshot)) return
      const next = { ...snapshot }
      delete next[id]
      snapshot = next
      emit()
    },
  }
}

export const runtimeStateStore: RuntimeStateStore = createRuntimeStateStore()
