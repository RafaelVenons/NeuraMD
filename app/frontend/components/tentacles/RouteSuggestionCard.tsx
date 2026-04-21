import { useState } from "react"
import { useNavigate } from "react-router-dom"

import type { RouteSuggestion } from "~/components/tentacles/types"

type Props = {
  suggestion: RouteSuggestion
  onDismiss: (id: string) => void
}

export function RouteSuggestionCard({ suggestion, onDismiss }: Props) {
  const navigate = useNavigate()
  const [prompt, setPrompt] = useState(suggestion.suggested_prompt)

  const openSession = () => {
    navigate(`/notes/${encodeURIComponent(suggestion.target.slug)}/tentacle`, {
      state: { initialPrompt: prompt },
    })
  }

  return (
    <section className="nm-route-suggestion">
      <header className="nm-route-suggestion__header">
        <span className="nm-route-suggestion__badge">Encaminhamento sugerido</span>
        <strong>{suggestion.target.title}</strong>
      </header>
      {suggestion.rationale ? (
        <p className="nm-route-suggestion__rationale">{suggestion.rationale}</p>
      ) : null}
      <label className="nm-route-suggestion__prompt">
        Prompt (editável)
        <textarea
          value={prompt}
          onChange={(event) => setPrompt(event.target.value)}
          rows={6}
        />
      </label>
      <div className="nm-route-suggestion__actions">
        <button type="button" className="nm-button" onClick={openSession} disabled={!prompt.trim()}>
          Abrir sessão
        </button>
        <button type="button" className="nm-button nm-button--ghost" onClick={() => onDismiss(suggestion.id)}>
          Dispensar
        </button>
      </div>
    </section>
  )
}
