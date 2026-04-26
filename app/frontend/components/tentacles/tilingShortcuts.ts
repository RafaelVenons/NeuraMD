import { useEffect } from "react"

export type TilingShortcut =
  | { kind: "focusIndex"; index: number }
  | { kind: "next" }
  | { kind: "previous" }
  | { kind: "soloToggle" }
  | { kind: "focusGraph" }

export function selectTileByIndex(ids: string[], oneBasedIndex: number): string | null {
  if (oneBasedIndex < 1 || oneBasedIndex > ids.length) return null
  return ids[oneBasedIndex - 1] ?? null
}

export function selectNextTileId(ids: string[], currentId: string | null): string | null {
  if (ids.length === 0) return null
  if (currentId === null) return ids[0] ?? null
  const idx = ids.indexOf(currentId)
  if (idx < 0) return ids[0] ?? null
  return ids[(idx + 1) % ids.length] ?? null
}

export function selectPreviousTileId(ids: string[], currentId: string | null): string | null {
  if (ids.length === 0) return null
  const last = ids[ids.length - 1] ?? null
  if (currentId === null) return last
  const idx = ids.indexOf(currentId)
  if (idx < 0) return last
  return ids[(idx - 1 + ids.length) % ids.length] ?? null
}

export function resolveTilingShortcut(event: KeyboardEvent): TilingShortcut | null {
  if (!event.altKey) return null
  if (event.ctrlKey || event.metaKey) return null
  const key = event.key
  if (/^[1-9]$/.test(key)) return { kind: "focusIndex", index: Number(key) }
  const lower = key.toLowerCase()
  if (lower === "j") return { kind: "next" }
  if (lower === "k") return { kind: "previous" }
  if (lower === "m") return { kind: "soloToggle" }
  if (lower === "g") return { kind: "focusGraph" }
  return null
}

type Handlers = {
  tileIds: string[]
  focusedId: string | null
  onFocusId: (id: string) => void
  onSoloToggle: () => void
  onFocusGraph: () => void
}

export function useTilingShortcuts(handlers: Handlers): void {
  const { tileIds, focusedId, onFocusId, onSoloToggle, onFocusGraph } = handlers

  useEffect(() => {
    if (typeof window === "undefined") return

    const onKey = (event: KeyboardEvent) => {
      const shortcut = resolveTilingShortcut(event)
      if (!shortcut) return
      if (shortcut.kind === "focusIndex") {
        const id = selectTileByIndex(tileIds, shortcut.index)
        if (id === null) return
        event.preventDefault()
        onFocusId(id)
        return
      }
      if (shortcut.kind === "next") {
        const id = selectNextTileId(tileIds, focusedId)
        if (id === null) return
        event.preventDefault()
        onFocusId(id)
        return
      }
      if (shortcut.kind === "previous") {
        const id = selectPreviousTileId(tileIds, focusedId)
        if (id === null) return
        event.preventDefault()
        onFocusId(id)
        return
      }
      if (shortcut.kind === "soloToggle") {
        event.preventDefault()
        onSoloToggle()
        return
      }
      if (shortcut.kind === "focusGraph") {
        event.preventDefault()
        onFocusGraph()
      }
    }

    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [tileIds, focusedId, onFocusId, onSoloToggle, onFocusGraph])
}
