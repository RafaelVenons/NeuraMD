import { useEffect, useState } from "react"

import type { TagAdminDto, TagAdminResponse } from "~/components/settings/types"
import { fetchJson } from "~/runtime/fetchJson"

export function TagsTab() {
  const [tags, setTags] = useState<TagAdminDto[]>([])
  const [status, setStatus] = useState<"loading" | "idle" | "error">("loading")
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    fetchJson<TagAdminResponse>("/api/tags?scope=all")
      .then((res) => {
        setTags([...res.tags].sort((a, b) => b.notes_count - a.notes_count))
        setStatus("idle")
      })
      .catch((err: unknown) => {
        setStatus("error")
        setMessage(err instanceof Error ? err.message : "Erro ao carregar")
      })
  }, [])

  if (status === "loading") return <p className="nm-settings-placeholder">Carregando…</p>
  if (status === "error") return <p className="nm-settings-properties__error">{message}</p>

  return (
    <div className="nm-settings-list">
      <p className="nm-settings-list__hint">
        Admin read-only — edição de nome/cor ainda vive na UI legacy em <code>/tags</code>.
      </p>
      {tags.length === 0 ? (
        <p className="nm-settings-list__empty">Sem tags cadastradas.</p>
      ) : (
        <table className="nm-settings-tags">
          <thead>
            <tr>
              <th>Nome</th>
              <th>Escopo</th>
              <th>Notas</th>
              <th>Cor</th>
            </tr>
          </thead>
          <tbody>
            {tags.map((tag) => (
              <tr key={tag.id}>
                <td>{tag.name}</td>
                <td>
                  <span className="nm-settings-list__chip">{tag.tag_scope}</span>
                </td>
                <td>{tag.notes_count}</td>
                <td>
                  {tag.color_hex ? (
                    <span
                      className="nm-settings-tags__swatch"
                      style={{ background: tag.color_hex }}
                      title={tag.color_hex}
                    />
                  ) : (
                    <span className="nm-settings-list__meta">—</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
