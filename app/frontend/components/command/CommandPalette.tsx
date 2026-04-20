import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useNavigate } from "react-router-dom"

import type { SearchResponse, SearchResult } from "~/components/command/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  open: boolean
  onClose: () => void
}

export function CommandPalette({ open, onClose }: Props) {
  const [query, setQuery] = useState("")
  const [results, setResults] = useState<SearchResult[]>([])
  const [active, setActive] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)
  const navigate = useNavigate()
  const debounceRef = useRef<number | null>(null)

  useEffect(() => {
    if (!open) return
    setQuery("")
    setResults([])
    setActive(0)
    setError(null)
    inputRef.current?.focus()
  }, [open])

  useEffect(() => {
    if (!open) return
    if (debounceRef.current) window.clearTimeout(debounceRef.current)

    debounceRef.current = window.setTimeout(() => {
      void runSearch(query)
    }, 150)

    return () => {
      if (debounceRef.current) window.clearTimeout(debounceRef.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, query])

  const runSearch = useCallback(async (term: string) => {
    setLoading(true)
    setError(null)
    try {
      const qs = new URLSearchParams({ q: term, limit: "12" }).toString()
      const res = await fetchJson<SearchResponse>(`/api/notes/search?${qs}`)
      setResults(res.results)
      setActive(0)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erro ao buscar")
      setResults([])
    } finally {
      setLoading(false)
    }
  }, [])

  const hint = useMemo(() => {
    if (loading) return "Buscando…"
    if (error) return error
    if (results.length === 0 && query.trim().length > 0) return "Sem resultados."
    return `${results.length} resultado(s) · Tab para DSL (tag:, status:, created:)`
  }, [loading, error, results.length, query])

  const openResult = useCallback(
    (result: SearchResult) => {
      navigate(`/notes/${result.slug}`)
      onClose()
    },
    [navigate, onClose]
  )

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape") {
      event.preventDefault()
      onClose()
      return
    }
    if (event.key === "ArrowDown") {
      event.preventDefault()
      setActive((prev) => (results.length === 0 ? 0 : (prev + 1) % results.length))
      return
    }
    if (event.key === "ArrowUp") {
      event.preventDefault()
      setActive((prev) => (results.length === 0 ? 0 : (prev - 1 + results.length) % results.length))
      return
    }
    if (event.key === "Enter") {
      const chosen = results[active]
      if (chosen) {
        event.preventDefault()
        openResult(chosen)
      }
    }
  }

  if (!open) return null

  return (
    <div
      className="nm-command-palette"
      role="dialog"
      aria-modal="true"
      aria-label="Buscar notas"
      onKeyDown={onKeyDown}
    >
      <button
        type="button"
        className="nm-command-palette__backdrop"
        aria-label="Fechar"
        onClick={onClose}
      />
      <div className="nm-command-palette__panel">
        <input
          ref={inputRef}
          type="text"
          className="nm-command-palette__input"
          placeholder="Buscar notas… (tag:plan status:open)"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <p className="nm-command-palette__hint">{hint}</p>
        <ul className="nm-command-palette__results">
          {results.map((result, idx) => (
            <li
              key={result.id}
              className={
                idx === active
                  ? "nm-command-palette__item is-active"
                  : "nm-command-palette__item"
              }
            >
              <button
                type="button"
                className="nm-command-palette__item-btn"
                onMouseEnter={() => setActive(idx)}
                onClick={() => openResult(result)}
              >
                <span className="nm-command-palette__item-title">{result.title}</span>
                {result.snippet ? (
                  <span className="nm-command-palette__item-snippet">{result.snippet}</span>
                ) : null}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
