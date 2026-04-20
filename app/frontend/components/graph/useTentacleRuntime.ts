import { useEffect, useState } from "react"

import { fetchJson } from "~/runtime/fetchJson"

type RuntimeResponse = { alive_ids: string[] }

export function useTentacleRuntime(intervalMs = 5000): Set<string> {
  const [aliveIds, setAliveIds] = useState<Set<string>>(() => new Set())

  useEffect(() => {
    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | null = null

    const poll = async () => {
      try {
        const data = await fetchJson<RuntimeResponse>("/api/tentacles/runtime")
        if (cancelled) return
        setAliveIds(new Set(data.alive_ids ?? []))
      } catch {
        if (cancelled) return
        setAliveIds(new Set())
      } finally {
        if (!cancelled) {
          timer = setTimeout(poll, intervalMs)
        }
      }
    }

    poll()

    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
    }
  }, [intervalMs])

  return aliveIds
}
