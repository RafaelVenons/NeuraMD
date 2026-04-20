import { useCallback, useEffect, useState } from "react"

import type { NotePayload } from "~/components/editor/types"
import type { ApiError } from "~/runtime/errors"
import { fetchJson } from "~/runtime/fetchJson"

export type NotePayloadState =
  | { status: "loading" }
  | { status: "ready"; payload: NotePayload; reload: () => void }
  | { status: "error"; error: ApiError | Error; reload: () => void }

export function useNotePayload(slug: string): NotePayloadState {
  const [state, setState] = useState<NotePayloadState>({ status: "loading" })
  const [nonce, setNonce] = useState(0)

  const reload = useCallback(() => {
    setNonce((n) => n + 1)
  }, [])

  useEffect(() => {
    let cancelled = false
    setState({ status: "loading" })

    fetchJson<NotePayload>(`/api/notes/${encodeURIComponent(slug)}`)
      .then((payload) => {
        if (cancelled) return
        setState({ status: "ready", payload, reload })
      })
      .catch((error: unknown) => {
        if (cancelled) return
        setState({
          status: "error",
          error: error instanceof Error ? error : new Error(String(error)),
          reload,
        })
      })

    return () => {
      cancelled = true
    }
  }, [slug, nonce, reload])

  return state
}
