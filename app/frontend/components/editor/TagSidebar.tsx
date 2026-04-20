import { useEffect, useRef, useState } from "react"

import type { NoteTag } from "~/components/editor/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  slug: string
  initialTags: NoteTag[]
}

type Suggestion = { id: number; name: string; color_hex: string | null }

type MutationStatus = "idle" | "saving" | "error"

export function TagSidebar({ slug, initialTags }: Props) {
  const [tags, setTags] = useState<NoteTag[]>(initialTags)
  const [suggestions, setSuggestions] = useState<Suggestion[]>([])
  const [name, setName] = useState("")
  const [color, setColor] = useState("#5cc8ff")
  const [status, setStatus] = useState<MutationStatus>("idle")
  const [message, setMessage] = useState<string | null>(null)
  const listId = useRef(`nm-tag-suggestions-${Math.random().toString(36).slice(2, 8)}`).current

  useEffect(() => {
    setTags(initialTags)
  }, [initialTags])

  useEffect(() => {
    let cancelled = false
    fetchJson<{ tags: Suggestion[] }>("/api/tags")
      .then((res) => {
        if (!cancelled) setSuggestions(res.tags)
      })
      .catch(() => {
        /* autocomplete is best-effort */
      })
    return () => {
      cancelled = true
    }
  }, [])

  const attach = async (event: React.FormEvent) => {
    event.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    setStatus("saving")
    setMessage(null)
    try {
      const res = await fetchJson<{ tags: NoteTag[] }>(
        `/api/notes/${encodeURIComponent(slug)}/tags`,
        { method: "POST", body: { name: trimmed, color_hex: color } }
      )
      setTags(res.tags)
      setName("")
      setStatus("idle")
    } catch (error) {
      setStatus("error")
      setMessage(error instanceof Error ? error.message : "Erro ao anexar tag")
    }
  }

  const detach = async (tag: NoteTag) => {
    setStatus("saving")
    setMessage(null)
    try {
      const res = await fetchJson<{ tags: NoteTag[] }>(
        `/api/notes/${encodeURIComponent(slug)}/tags/${tag.id}`,
        { method: "DELETE" }
      )
      setTags(res.tags)
      setStatus("idle")
    } catch (error) {
      setStatus("error")
      setMessage(error instanceof Error ? error.message : "Erro ao remover tag")
    }
  }

  return (
    <div className="nm-tag-sidebar">
      <header>
        <h2>Tags</h2>
        <p className="nm-editor-page__muted">
          {tags.length === 0 ? "Sem tags" : `${tags.length} tag(s)`}
        </p>
      </header>

      <ul className="nm-tag-sidebar__list">
        {tags.map((tag) => (
          <li key={tag.id} style={{ borderLeftColor: tag.color_hex ?? "#5cc8ff" }}>
            <span className="nm-tag-sidebar__name">{tag.name}</span>
            <button
              type="button"
              className="nm-tag-sidebar__remove"
              onClick={() => detach(tag)}
              aria-label={`Remover tag ${tag.name}`}
              title={`Remover ${tag.name}`}
            >
              ×
            </button>
          </li>
        ))}
      </ul>

      <form className="nm-tag-sidebar__form" onSubmit={attach}>
        <label htmlFor="nm-tag-new-name" className="nm-editor-page__muted">
          Nova tag
        </label>
        <div className="nm-tag-sidebar__row">
          <input
            id="nm-tag-new-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="nome"
            list={listId}
            autoComplete="off"
          />
          <input
            type="color"
            value={color}
            onChange={(e) => setColor(e.target.value)}
            aria-label="Cor da nova tag"
          />
          <button type="submit" disabled={status === "saving" || name.trim() === ""}>
            +
          </button>
        </div>
        <datalist id={listId}>
          {suggestions.map((s) => (
            <option key={s.id} value={s.name} />
          ))}
        </datalist>
      </form>

      {status === "error" && message ? (
        <p className="nm-tag-sidebar__error">{message}</p>
      ) : null}
    </div>
  )
}
