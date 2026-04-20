import { useEffect, useRef, useState } from "react"

import { fetchJson } from "~/runtime/fetchJson"

export type DraftStatus = "idle" | "dirty" | "saving" | "saved" | "error"

type Options = {
  slug: string
  content: string
  debounceMs?: number
}

type DraftResponse = { saved: boolean; kind: string; graph_changed: boolean }

export function useDraftAutosave({ slug, content, debounceMs = 60_000 }: Options) {
  const [status, setStatus] = useState<DraftStatus>("idle")
  const [savedAt, setSavedAt] = useState<Date | null>(null)
  const lastSavedRef = useRef<string | null>(null)
  const latestContentRef = useRef<string>(content)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const inflightRef = useRef<Promise<void> | null>(null)

  useEffect(() => {
    latestContentRef.current = content
  }, [content])

  useEffect(() => {
    lastSavedRef.current = null
    setStatus("idle")
    setSavedAt(null)
  }, [slug])

  useEffect(() => {
    if (lastSavedRef.current === null) {
      lastSavedRef.current = content
      return
    }
    if (content === lastSavedRef.current) {
      return
    }
    setStatus("dirty")
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      void flush()
    }, debounceMs)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [content, debounceMs, slug])

  const flush = async (): Promise<void> => {
    if (inflightRef.current) return inflightRef.current
    const snapshot = latestContentRef.current
    if (snapshot === lastSavedRef.current) return
    setStatus("saving")
    const promise = (async () => {
      try {
        await fetchJson<DraftResponse>(`/api/notes/${encodeURIComponent(slug)}/draft`, {
          method: "POST",
          body: { content_markdown: snapshot },
        })
        lastSavedRef.current = snapshot
        setStatus("saved")
        setSavedAt(new Date())
      } catch {
        setStatus("error")
      } finally {
        inflightRef.current = null
      }
    })()
    inflightRef.current = promise
    return promise
  }

  const cancelPending = () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }

  const markSynced = (syncedContent: string) => {
    cancelPending()
    lastSavedRef.current = syncedContent
    setStatus("idle")
  }

  return { status, savedAt, flushNow: flush, cancelPending, markSynced }
}
