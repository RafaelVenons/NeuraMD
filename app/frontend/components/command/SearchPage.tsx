import { useCallback, useEffect, useState } from "react"
import { Link } from "react-router-dom"

import type { SearchResponse, SearchResult } from "~/components/command/types"
import { fetchJson } from "~/runtime/fetchJson"

export function SearchPage() {
  const [query, setQuery] = useState("")
  const [results, setResults] = useState<SearchResult[]>([])
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle")
  const [message, setMessage] = useState<string | null>(null)

  const runSearch = useCallback(async (term: string) => {
    setStatus("loading")
    setMessage(null)
    try {
      const qs = new URLSearchParams({ q: term, limit: "25" }).toString()
      const res = await fetchJson<SearchResponse>(`/api/notes/search?${qs}`)
      setResults(res.results)
      setStatus("idle")
    } catch (err) {
      setStatus("error")
      setMessage(err instanceof Error ? err.message : "Erro ao buscar")
    }
  }, [])

  useEffect(() => {
    const t = window.setTimeout(() => void runSearch(query), 200)
    return () => window.clearTimeout(t)
  }, [query, runSearch])

  return (
    <section className="nm-search-page">
      <header className="nm-search-page__header">
        <h1>Busca</h1>
        <p className="nm-search-page__hint">
          Atalho global: <kbd>Cmd</kbd>+<kbd>K</kbd>. DSL: <code>tag:</code>, <code>status:</code>,{" "}
          <code>created:</code>.
        </p>
      </header>
      <input
        type="text"
        className="nm-search-page__input"
        placeholder="Buscar notas…"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      {status === "error" && message ? (
        <p className="nm-search-page__error">{message}</p>
      ) : null}
      <ul className="nm-search-page__results">
        {results.map((result) => (
          <li key={result.id} className="nm-search-page__result">
            <Link to={`/notes/${result.slug}`} className="nm-search-page__result-link">
              <span className="nm-search-page__result-title">{result.title}</span>
              {result.snippet ? (
                <span className="nm-search-page__result-snippet">{result.snippet}</span>
              ) : null}
            </Link>
          </li>
        ))}
      </ul>
      {status === "idle" && results.length === 0 ? (
        <p className="nm-search-page__empty">Sem resultados.</p>
      ) : null}
    </section>
  )
}
