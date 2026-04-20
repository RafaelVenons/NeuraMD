import { useState } from "react"

import type { PropertyDefinition, PropertyValueType } from "~/components/editor/types"
import { fetchJson } from "~/runtime/fetchJson"

type Props = {
  slug: string
  definitions: PropertyDefinition[]
  initialValues: Record<string, unknown>
  initialErrors: Record<string, unknown>
}

type PersistStatus = "idle" | "saving" | "saved" | "error"

export function PropertiesEditor({ slug, definitions, initialValues, initialErrors }: Props) {
  const [values, setValues] = useState<Record<string, unknown>>(initialValues)
  const [errors, setErrors] = useState<Record<string, unknown>>(initialErrors)
  const [status, setStatus] = useState<PersistStatus>("idle")
  const [statusMessage, setStatusMessage] = useState<string | null>(null)

  const commit = async (key: string, next: unknown) => {
    const before = values[key]
    setValues((prev) => ({ ...prev, [key]: next }))
    setStatus("saving")
    setStatusMessage(null)
    try {
      const response = await fetchJson<{
        properties: Record<string, unknown>
        properties_errors: Record<string, unknown>
      }>(`/api/notes/${encodeURIComponent(slug)}/properties`, {
        method: "PATCH",
        body: { changes: { [key]: next } },
      })
      setValues(response.properties)
      setErrors(response.properties_errors)
      setStatus("saved")
    } catch (error) {
      setValues((prev) => ({ ...prev, [key]: before }))
      setStatus("error")
      setStatusMessage(error instanceof Error ? error.message : "Erro desconhecido")
    }
  }

  if (definitions.length === 0) {
    return <p className="nm-editor-page__muted">Nenhuma definição ativa.</p>
  }

  return (
    <div className="nm-properties-editor">
      <div className={`nm-properties-editor__status nm-properties-editor__status--${status}`}>
        {labelFor(status, statusMessage)}
      </div>
      {definitions.map((def) => {
        const fieldError = errors[def.key]
        return (
          <div key={def.key} className="nm-properties-editor__field">
            <label htmlFor={`nm-prop-${def.key}`}>{def.label ?? def.key}</label>
            {def.description ? <p className="nm-properties-editor__desc">{def.description}</p> : null}
            <PropertyInput
              definition={def}
              value={values[def.key]}
              onCommit={(v) => commit(def.key, v)}
            />
            {fieldError ? (
              <p className="nm-properties-editor__error">{formatError(fieldError)}</p>
            ) : null}
          </div>
        )
      })}
    </div>
  )
}

type InputProps = {
  definition: PropertyDefinition
  value: unknown
  onCommit: (next: unknown) => void
}

function PropertyInput({ definition, value, onCommit }: InputProps) {
  switch (definition.value_type as PropertyValueType) {
    case "text":
    case "url":
    case "note_reference":
      return <TextField definition={definition} value={value} onCommit={onCommit} />
    case "long_text":
      return <LongTextField definition={definition} value={value} onCommit={onCommit} />
    case "number":
      return <NumberField definition={definition} value={value} onCommit={onCommit} />
    case "boolean":
      return <BooleanField definition={definition} value={value} onCommit={onCommit} />
    case "date":
      return <DateField definition={definition} value={value} onCommit={onCommit} type="date" />
    case "datetime":
      return <DateField definition={definition} value={value} onCommit={onCommit} type="datetime-local" />
    case "enum":
      return <EnumField definition={definition} value={value} onCommit={onCommit} />
    case "multi_enum":
      return <MultiEnumField definition={definition} value={value} onCommit={onCommit} />
    case "list":
      return <ListField definition={definition} value={value} onCommit={onCommit} />
    default:
      return (
        <input id={`nm-prop-${definition.key}`} type="text" disabled value={`Tipo desconhecido: ${definition.value_type}`} />
      )
  }
}

function TextField({ definition, value, onCommit }: InputProps) {
  const [draft, setDraft] = useState(toStringValue(value))
  return (
    <input
      id={`nm-prop-${definition.key}`}
      type="text"
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        const next = draft.trim() === "" ? null : draft
        if (next !== value) onCommit(next)
      }}
    />
  )
}

function LongTextField({ definition, value, onCommit }: InputProps) {
  const [draft, setDraft] = useState(toStringValue(value))
  return (
    <textarea
      id={`nm-prop-${definition.key}`}
      rows={3}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        const next = draft === "" ? null : draft
        if (next !== value) onCommit(next)
      }}
    />
  )
}

function NumberField({ definition, value, onCommit }: InputProps) {
  const [draft, setDraft] = useState(toStringValue(value))
  return (
    <input
      id={`nm-prop-${definition.key}`}
      type="number"
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        if (draft === "") {
          if (value !== null && value !== undefined) onCommit(null)
          return
        }
        const parsed = Number(draft)
        if (!Number.isNaN(parsed) && parsed !== value) onCommit(parsed)
      }}
    />
  )
}

function BooleanField({ definition, value, onCommit }: InputProps) {
  const checked = value === true
  return (
    <input
      id={`nm-prop-${definition.key}`}
      type="checkbox"
      checked={checked}
      onChange={(e) => onCommit(e.target.checked)}
    />
  )
}

type DateProps = InputProps & { type: "date" | "datetime-local" }

function DateField({ definition, value, onCommit, type }: DateProps) {
  const [draft, setDraft] = useState(toStringValue(value))
  return (
    <input
      id={`nm-prop-${definition.key}`}
      type={type}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        const next = draft === "" ? null : draft
        if (next !== value) onCommit(next)
      }}
    />
  )
}

function EnumField({ definition, value, onCommit }: InputProps) {
  const options = (definition.config?.options as string[] | undefined) ?? []
  const current = toStringValue(value)
  return (
    <select
      id={`nm-prop-${definition.key}`}
      value={current}
      onChange={(e) => {
        const next = e.target.value === "" ? null : e.target.value
        onCommit(next)
      }}
    >
      <option value="">—</option>
      {options.map((opt) => (
        <option key={opt} value={opt}>
          {opt}
        </option>
      ))}
    </select>
  )
}

function MultiEnumField({ definition, value, onCommit }: InputProps) {
  const options = (definition.config?.options as string[] | undefined) ?? []
  const selected = new Set(Array.isArray(value) ? (value as string[]) : [])
  return (
    <div className="nm-properties-editor__checkgroup">
      {options.map((opt) => (
        <label key={opt}>
          <input
            type="checkbox"
            checked={selected.has(opt)}
            onChange={(e) => {
              const next = new Set(selected)
              if (e.target.checked) next.add(opt)
              else next.delete(opt)
              onCommit(Array.from(next))
            }}
          />
          {opt}
        </label>
      ))}
    </div>
  )
}

function ListField({ definition, value, onCommit }: InputProps) {
  const items = Array.isArray(value) ? (value as unknown[]).map(toStringValue) : []
  const [draft, setDraft] = useState(items.join("\n"))
  return (
    <textarea
      id={`nm-prop-${definition.key}`}
      rows={3}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      placeholder="Um item por linha"
      onBlur={() => {
        const parts = draft
          .split("\n")
          .map((s) => s.trim())
          .filter((s) => s.length > 0)
        onCommit(parts.length === 0 ? null : parts)
      }}
    />
  )
}

function toStringValue(value: unknown): string {
  if (value === null || value === undefined) return ""
  if (typeof value === "string") return value
  if (typeof value === "number" || typeof value === "boolean") return String(value)
  return JSON.stringify(value)
}

function formatError(error: unknown): string {
  if (Array.isArray(error)) return error.join(", ")
  if (typeof error === "string") return error
  if (error && typeof error === "object") return JSON.stringify(error)
  return "Erro de validação"
}

function labelFor(status: PersistStatus, message: string | null): string {
  switch (status) {
    case "idle":
      return "Pronto"
    case "saving":
      return "Salvando propriedade…"
    case "saved":
      return "Salvo"
    case "error":
      return message ? `Erro: ${message}` : "Erro ao salvar"
  }
}
