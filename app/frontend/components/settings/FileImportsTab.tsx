import { useEffect, useState } from "react"

import type { FileImportDto, FileImportsResponse } from "~/components/settings/types"
import { fetchJson } from "~/runtime/fetchJson"

export function FileImportsTab() {
  const [imports, setImports] = useState<FileImportDto[]>([])
  const [status, setStatus] = useState<"loading" | "idle" | "error">("loading")
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    fetchJson<FileImportsResponse>("/api/file_imports")
      .then((res) => {
        setImports(res.imports)
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
        Novos imports ainda são enviados pela tela legacy em <code>/file_imports/new</code>.
      </p>
      {imports.length === 0 ? (
        <p className="nm-settings-list__empty">Sem imports por enquanto.</p>
      ) : (
        <ul className="nm-settings-list__rows">
          {imports.map((fi) => (
            <li key={fi.id} className="nm-settings-list__row">
              <div>
                <strong>{fi.original_filename}</strong>
                <span className={`nm-settings-list__chip is-${fi.status}`}>{fi.status}</span>
              </div>
              <p className="nm-settings-list__meta">
                tag <code>{fi.base_tag}</code> · lote <code>{fi.import_tag}</code>
                {fi.notes_created ? ` · ${fi.notes_created} notas` : ""}
              </p>
              {fi.error_message ? (
                <p className="nm-settings-list__error">{fi.error_message}</p>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
