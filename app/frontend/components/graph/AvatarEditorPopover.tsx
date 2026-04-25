import { useEffect, useId, useRef, useState } from "react"

import { ClawdAvatar } from "~/components/graph/ClawdAvatar"
import { AGENT_ROLE_PALETTE, DEFAULT_AGENT_COLOR } from "~/components/graph/agentPalette"
import type { AvatarHat, AvatarState, AvatarVariant, GraphNote } from "~/components/graph/types"
import { fetchJson } from "~/runtime/fetchJson"

const HAT_OPTIONS: { value: AvatarHat; label: string }[] = [
  { value: "none", label: "Sem chapéu" },
  { value: "cartola", label: "Cartola" },
  { value: "chef", label: "Chef" },
]

const VARIANT_OPTIONS: { value: AvatarVariant; label: string }[] = [
  { value: "clawd-v1", label: "Clawd v1" },
]

const HEX_PATTERN = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/

const PALETTE_SWATCHES = Array.from(
  new Set(Object.values(AGENT_ROLE_PALETTE).concat(DEFAULT_AGENT_COLOR))
)

type Props = {
  note: GraphNote
  anchor: { x: number; y: number }
  onClose: () => void
  onSaved: (next: { color: string; hat: AvatarHat; variant: AvatarVariant }) => void
  onOpenNote: (slug: string) => void
}

type Status = "idle" | "saving" | "error"

export function AvatarEditorPopover({ note, anchor, onClose, onSaved, onOpenNote }: Props) {
  const initial = note.avatar
  const initialColor = initial?.color ?? DEFAULT_AGENT_COLOR
  const initialHat: AvatarHat = initial?.hat ?? "none"
  const initialVariant: AvatarVariant = initial?.variant ?? "clawd-v1"
  const initialState: AvatarState = initial?.state ?? "sleeping"

  const [color, setColor] = useState<string>(initialColor)
  const [hatValue, setHatValue] = useState<AvatarHat>(initialHat)
  const [variant, setVariant] = useState<AvatarVariant>(initialVariant)
  const [hexInput, setHexInput] = useState<string>(initialColor)
  const [status, setStatus] = useState<Status>("idle")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const ref = useRef<HTMLDivElement | null>(null)
  const titleId = useId()

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose()
    }
    window.addEventListener("keydown", onKey)
    window.addEventListener("mousedown", onClick)
    return () => {
      window.removeEventListener("keydown", onKey)
      window.removeEventListener("mousedown", onClick)
    }
  }, [onClose])

  const dirty =
    color !== initialColor || hatValue !== initialHat || variant !== initialVariant

  const isValidHex = HEX_PATTERN.test(color)

  const handleHexChange = (raw: string) => {
    setHexInput(raw)
    if (HEX_PATTERN.test(raw)) setColor(raw)
  }

  const handleSwatchClick = (swatch: string) => {
    setColor(swatch)
    setHexInput(swatch)
  }

  const handleSave = async () => {
    if (!isValidHex) {
      setStatus("error")
      setErrorMessage("Cor precisa ser hex válido (#rgb ou #rrggbb).")
      return
    }
    setStatus("saving")
    setErrorMessage(null)
    try {
      await fetchJson<{
        properties: Record<string, unknown>
        properties_errors: Record<string, unknown>
      }>(`/api/notes/${encodeURIComponent(note.slug)}/properties`, {
        method: "PATCH",
        body: {
          changes: {
            avatar_color: color,
            avatar_hat: hatValue,
            avatar_variant: variant,
          },
        },
      })
      onSaved({ color, hat: hatValue, variant })
      onClose()
    } catch (error) {
      setStatus("error")
      setErrorMessage(error instanceof Error ? error.message : "Falha ao salvar.")
    }
  }

  // Anchor near the click but clamped within viewport. The popover renders
  // at fixed coords; positioning math stays in here so the host doesn't need
  // to think about overflow.
  const POPOVER_W = 260
  const POPOVER_H = 360
  const margin = 12
  const x = Math.min(
    Math.max(anchor.x + margin, margin),
    window.innerWidth - POPOVER_W - margin
  )
  const y = Math.min(
    Math.max(anchor.y + margin, margin),
    window.innerHeight - POPOVER_H - margin
  )

  return (
    <div
      ref={ref}
      role="dialog"
      aria-labelledby={titleId}
      className="nm-avatar-editor"
      style={{ position: "fixed", top: y, left: x, width: POPOVER_W }}
    >
      <header className="nm-avatar-editor__header">
        <h3 id={titleId}>{note.title}</h3>
        <button
          type="button"
          className="nm-avatar-editor__close"
          onClick={onClose}
          aria-label="Fechar editor"
        >
          ×
        </button>
      </header>

      <div className="nm-avatar-editor__preview" aria-hidden>
        <svg width={72} height={72} viewBox="-36 -36 72 72">
          <ClawdAvatar state={initialState} color={color} hat={hatValue} size={64} />
        </svg>
      </div>

      <div className="nm-avatar-editor__field">
        <label>Cor</label>
        <div className="nm-avatar-editor__swatches" role="radiogroup" aria-label="Paleta de cores">
          {PALETTE_SWATCHES.map((swatch) => (
            <button
              type="button"
              key={swatch}
              role="radio"
              aria-checked={swatch === color}
              aria-label={`Cor ${swatch}`}
              className={`nm-avatar-editor__swatch${
                swatch === color ? " is-selected" : ""
              }`}
              style={{ backgroundColor: swatch }}
              onClick={() => handleSwatchClick(swatch)}
            />
          ))}
        </div>
        <input
          type="text"
          className="nm-avatar-editor__hex"
          value={hexInput}
          onChange={(e) => handleHexChange(e.target.value)}
          aria-label="Cor custom hex"
          placeholder="#rrggbb"
          spellCheck={false}
        />
      </div>

      <div className="nm-avatar-editor__field">
        <label htmlFor={`${titleId}-hat`}>Chapéu</label>
        <select
          id={`${titleId}-hat`}
          value={hatValue}
          onChange={(e) => setHatValue(e.target.value as AvatarHat)}
        >
          {HAT_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>

      <div className="nm-avatar-editor__field">
        <label htmlFor={`${titleId}-variant`}>Variante</label>
        <select
          id={`${titleId}-variant`}
          value={variant}
          onChange={(e) => setVariant(e.target.value as AvatarVariant)}
        >
          {VARIANT_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>

      {status === "error" && errorMessage ? (
        <p className="nm-avatar-editor__error">{errorMessage}</p>
      ) : null}

      <footer className="nm-avatar-editor__footer">
        <button
          type="button"
          className="nm-avatar-editor__open"
          onClick={() => onOpenNote(note.slug)}
        >
          Abrir nota
        </button>
        <div className="nm-avatar-editor__actions">
          <button type="button" className="nm-button nm-button--ghost" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="button"
            className="nm-button"
            onClick={handleSave}
            disabled={!dirty || !isValidHex || status === "saving"}
          >
            {status === "saving" ? "Salvando…" : "Salvar"}
          </button>
        </div>
      </footer>
    </div>
  )
}
