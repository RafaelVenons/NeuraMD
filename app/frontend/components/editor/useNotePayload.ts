import { useEffect, useState } from "react"

import type { NotePayload } from "~/components/editor/types"
import type { ApiError } from "~/runtime/errors"
import { fetchJson } from "~/runtime/fetchJson"

export type NotePayloadState =
  | { status: "loading" }
  | { status: "ready"; payload: NotePayload }
  | { status: "error"; error: ApiError | Error }

export function useNotePayload(slug: string): NotePayloadState {
  const [state, setState] = useState<NotePayloadState>({ status: "loading" })

  useEffect(() => {
    let cancelled = false
    setState({ status: "loading" })

    fetchJson<NotePayload>(`/api/notes/${encodeURIComponent(slug)}`)
      .then((payload) => {
        if (cancelled) return
        setState({ status: "ready", payload })
      })
      .catch((error: unknown) => {
        if (cancelled) return
        setState({
          status: "error",
          error: error instanceof Error ? error : new Error(String(error)),
        })
      })

    return () => {
      cancelled = true
    }
  }, [slug])

  return state
}
