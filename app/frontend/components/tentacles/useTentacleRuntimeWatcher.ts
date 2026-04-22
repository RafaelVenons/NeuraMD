import { type ReactElement, useEffect } from "react"

import type { TentacleCableMessage } from "~/components/tentacles/types"
import { getCableConsumer } from "~/runtime/cable"
import {
  type RuntimeEvent,
  deriveStateFromEvent,
} from "~/runtime/runtimeStateMachine"
import { runtimeStateStore } from "~/runtime/runtimeStateStore"

const SILENCE_THRESHOLD_MS = 2000

type CableSubscription = {
  unsubscribe: () => void
}

export function TentacleRuntimeWatcherMount({
  tentacleId,
}: {
  tentacleId: string
}): ReactElement | null {
  useTentacleRuntimeWatcher(tentacleId)
  return null
}

export function useTentacleRuntimeWatcher(tentacleId: string | null | undefined): void {
  useEffect(() => {
    if (!tentacleId) return

    let silenceTimer: number | null = null

    const push = (event: RuntimeEvent) => {
      const prev = runtimeStateStore.getSnapshot()[tentacleId]?.state ?? null
      runtimeStateStore.setState(tentacleId, deriveStateFromEvent(prev, event))
      if (silenceTimer != null) {
        window.clearTimeout(silenceTimer)
        silenceTimer = null
      }
      if (event.type === "input" || event.type === "output") {
        const scheduledFor = runtimeStateStore.getActivityAt(tentacleId)
        silenceTimer = window.setTimeout(() => {
          silenceTimer = null
          const latest = runtimeStateStore.getActivityAt(tentacleId)
          if (latest !== scheduledFor) return
          push({ type: "silence" })
        }, SILENCE_THRESHOLD_MS)
      }
    }

    const consumer = getCableConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: "TentacleChannel", tentacle_id: tentacleId },
      {
        received: (msg: TentacleCableMessage | null) => {
          if (!msg) return
          if (msg.type === "output") push({ type: "output" })
          else if (msg.type === "exit") push({ type: "exit" })
        },
      }
    ) as unknown as CableSubscription

    return () => {
      if (silenceTimer != null) {
        window.clearTimeout(silenceTimer)
        silenceTimer = null
      }
      subscription.unsubscribe()
    }
  }, [tentacleId])
}
