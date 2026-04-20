import { useCallback, useEffect, useState } from "react"

import type {
  PropertyDefinitionDto,
  PropertyDefinitionResponse,
  PropertyDefinitionsResponse,
  PropertyValueType
} from "~/components/settings/types"
import { fetchJson } from "~/runtime/fetchJson"

const VALUE_TYPES: PropertyValueType[] = [
  "text",
  "long_text",
  "number",
  "boolean",
  "date",
  "datetime",
  "enum",
  "multi_enum",
  "url",
  "note_reference",
  "list"
]

type FormState = {
  key: string
  label: string
  value_type: PropertyValueType
  options: string
}

const emptyForm: FormState = {
  key: "",
  label: "",
  value_type: "text",
  options: ""
}

export function PropertyDefinitionsTab() {
  const [items, setItems] = useState<PropertyDefinitionDto[]>([])
  const [status, setStatus] = useState<"loading" | "idle" | "error">("loading")
  const [message, setMessage] = useState<string | null>(null)
  const [form, setForm] = useState<FormState>(emptyForm)

  const load = useCallback(async () => {
    setStatus("loading")
    setMessage(null)
    try {
      const res = await fetchJson<PropertyDefinitionsResponse>("/api/property_definitions")
      setItems(res.definitions)
      setStatus("idle")
    } catch (err) {
      setStatus("error")
      setMessage(err instanceof Error ? err.message : "Erro ao carregar propriedades")
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const create = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!form.key.trim()) return
    const config: Record<string, unknown> = {}
    if (form.value_type === "enum" || form.value_type === "multi_enum") {
      config.options = form.options
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
    }
    try {
      await fetchJson<PropertyDefinitionResponse>("/api/property_definitions", {
        method: "POST",
        body: JSON.stringify({
          property_definition: {
            key: form.key.trim(),
            value_type: form.value_type,
            label: form.label.trim() || null,
            config
          }
        })
      })
      setForm(emptyForm)
      await load()
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Erro ao criar")
    }
  }

  const archive = async (id: string) => {
    if (!window.confirm("Arquivar esta propriedade?")) return
    try {
      await fetchJson(`/api/property_definitions/${id}`, { method: "DELETE" })
      await load()
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Erro ao arquivar")
    }
  }

  const renameLabel = async (definition: PropertyDefinitionDto, label: string) => {
    if (label === (definition.label ?? "")) return
    try {
      await fetchJson<PropertyDefinitionResponse>(`/api/property_definitions/${definition.id}`, {
        method: "PATCH",
        body: JSON.stringify({ property_definition: { label } })
      })
      await load()
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Erro ao salvar")
    }
  }

  return (
    <div className="nm-settings-properties">
      <form className="nm-settings-properties__form" onSubmit={create}>
        <div className="nm-settings-properties__row">
          <input
            type="text"
            required
            placeholder="chave (ex: status)"
            value={form.key}
            onChange={(e) => setForm({ ...form, key: e.target.value })}
          />
          <input
            type="text"
            placeholder="label opcional"
            value={form.label}
            onChange={(e) => setForm({ ...form, label: e.target.value })}
          />
          <select
            value={form.value_type}
            onChange={(e) => setForm({ ...form, value_type: e.target.value as PropertyValueType })}
          >
            {VALUE_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <button type="submit" className="nm-button">
            Adicionar
          </button>
        </div>
        {(form.value_type === "enum" || form.value_type === "multi_enum") && (
          <input
            type="text"
            placeholder="opções separadas por vírgula"
            value={form.options}
            onChange={(e) => setForm({ ...form, options: e.target.value })}
          />
        )}
      </form>

      {message ? <p className="nm-settings-properties__error">{message}</p> : null}

      {status === "loading" ? (
        <p className="nm-settings-properties__meta">Carregando…</p>
      ) : items.length === 0 ? (
        <p className="nm-settings-properties__meta">Nenhuma propriedade cadastrada.</p>
      ) : (
        <ul className="nm-settings-properties__list">
          {items.map((definition) => (
            <li key={definition.id} className="nm-settings-properties__item">
              <div className="nm-settings-properties__item-head">
                <code>{definition.key}</code>
                <span className="nm-settings-properties__type">{definition.value_type}</span>
                {definition.system ? <span className="nm-settings-properties__chip">sistema</span> : null}
              </div>
              <input
                type="text"
                className="nm-settings-properties__label"
                defaultValue={definition.label ?? ""}
                placeholder="label"
                onBlur={(e) => void renameLabel(definition, e.target.value)}
              />
              {!definition.system && (
                <button
                  type="button"
                  className="nm-button nm-button--danger"
                  onClick={() => void archive(definition.id)}
                >
                  Arquivar
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
