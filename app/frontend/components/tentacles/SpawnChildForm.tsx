import { useState } from "react"
import { Link } from "react-router-dom"

import type { SpawnChildResponse } from "~/components/tentacles/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  parentSlug: string
}

type Status = "idle" | "saving" | "error"

export function SpawnChildForm({ parentSlug }: Props) {
  const [title, setTitle] = useState("")
  const [description, setDescription] = useState("")
  const [status, setStatus] = useState<Status>("idle")
  const [error, setError] = useState<string | null>(null)
  const [last, setLast] = useState<SpawnChildResponse | null>(null)

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!title.trim()) return
    setStatus("saving")
    setError(null)
    try {
      const res = await fetchJson<SpawnChildResponse>(
        `/api/notes/${encodeURIComponent(parentSlug)}/tentacle/children`,
        {
          method: "POST",
          body: { title: title.trim(), description: description.trim() || undefined },
        }
      )
      setLast(res)
      setTitle("")
      setDescription("")
      setStatus("idle")
    } catch (err) {
      setStatus("error")
      setError(err instanceof Error ? err.message : "Erro ao criar tentáculo")
    }
  }

  return (
    <section className="nm-tentacle-spawn">
      <header>
        <h3>Novo tentáculo-filho</h3>
      </header>
      <form onSubmit={submit} className="nm-tentacle-spawn__form">
        <label>
          Título
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="ex: Investigar bug X"
            required
          />
        </label>
        <label>
          Descrição (opcional)
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
          />
        </label>
        <button type="submit" className="nm-button" disabled={status === "saving" || !title.trim()}>
          {status === "saving" ? "Criando…" : "Criar filho"}
        </button>
      </form>
      {status === "error" && error ? (
        <p className="nm-tentacle-spawn__error">{error}</p>
      ) : null}
      {last ? (
        <p className="nm-tentacle-spawn__last">
          Criado:{" "}
          <Link to={`/notes/${last.slug}/tentacle`}>{last.title}</Link>
        </p>
      ) : null}
    </section>
  )
}
