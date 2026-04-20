import { useEffect, useState } from "react"
import { useParams } from "react-router-dom"

import { EditorPane } from "~/components/editor/EditorPane"
import { PreviewPane } from "~/components/editor/PreviewPane"
import { PropertiesEditor } from "~/components/editor/PropertiesEditor"
import type { NotePayload } from "~/components/editor/types"
import { useDraftAutosave, type DraftStatus } from "~/components/editor/useDraftAutosave"
import { useNotePayload } from "~/components/editor/useNotePayload"

export function EditorPage() {
  const { slug = "" } = useParams()
  const state = useNotePayload(slug)

  if (state.status === "loading") {
    return <div className="nm-editor-page__status">Carregando nota…</div>
  }

  if (state.status === "error") {
    return (
      <div className="nm-editor-page__status nm-editor-page__status--error">
        Erro ao carregar nota: {state.error.message}
      </div>
    )
  }

  return <EditorLoaded key={slug} slug={slug} initialContent={state.payload.revision.content_markdown} payload={state.payload} />
}

function EditorLoaded({
  slug,
  initialContent,
  payload,
}: {
  slug: string
  initialContent: string
  payload: NotePayload
}) {
  const [content, setContent] = useState(initialContent)
  const { status, savedAt, flushNow } = useDraftAutosave({ slug, content })

  useEffect(() => {
    setContent(initialContent)
  }, [initialContent])

  return (
    <div className="nm-editor-page">
      <aside className="nm-editor-page__tags">
        <header>
          <h2>Tags</h2>
          <p className="nm-editor-page__muted">
            {payload.tags.length === 0 ? "Sem tags" : `${payload.tags.length} tag(s)`}
          </p>
        </header>
        <ul className="nm-editor-page__tag-list">
          {payload.tags.map((tag) => (
            <li key={tag.id} style={{ borderLeftColor: tag.color_hex ?? "#5cc8ff" }}>
              {tag.name}
            </li>
          ))}
        </ul>
      </aside>

      <section className="nm-editor-page__editor">
        <header className="nm-editor-page__header">
          <h1>{payload.note.title}</h1>
          <div className="nm-editor-page__toolbar">
            <p className="nm-editor-page__muted">
              {payload.note.slug}
              {payload.revision.updated_at ? ` · atualizado em ${payload.revision.updated_at}` : ""}
            </p>
            <DraftStatusBadge status={status} savedAt={savedAt} onFlushNow={flushNow} />
          </div>
        </header>
        <EditorPane value={content} onChange={setContent} />
      </section>

      <section className="nm-editor-page__preview">
        <header>
          <h2>Preview</h2>
          <p className="nm-editor-page__muted">Renderização marked.js · wikilinks, KaTeX, highlight.js.</p>
        </header>
        <PreviewPane content={content} />
      </section>

      <aside className="nm-editor-page__properties">
        <header>
          <h2>Propriedades</h2>
          <p className="nm-editor-page__muted">
            {payload.property_definitions.length === 0
              ? "Sem definições ativas"
              : `${payload.property_definitions.length} definição(ões)`}
          </p>
        </header>
        <PropertiesEditor
          slug={slug}
          definitions={payload.property_definitions}
          initialValues={payload.properties}
          initialErrors={payload.properties_errors}
        />
        {payload.aliases.length > 0 ? (
          <section className="nm-editor-page__aliases">
            <h3>Aliases</h3>
            <ul>
              {payload.aliases.map((alias) => (
                <li key={alias}>{alias}</li>
              ))}
            </ul>
          </section>
        ) : null}
      </aside>
    </div>
  )
}

function DraftStatusBadge({
  status,
  savedAt,
  onFlushNow,
}: {
  status: DraftStatus
  savedAt: Date | null
  onFlushNow: () => void
}) {
  const label = labelFor(status, savedAt)
  const isDirty = status === "dirty" || status === "error"
  return (
    <button
      type="button"
      className={`nm-editor-page__draft-badge nm-editor-page__draft-badge--${status}`}
      onClick={isDirty ? onFlushNow : undefined}
      disabled={!isDirty}
      title={isDirty ? "Clique para salvar rascunho agora" : undefined}
    >
      {label}
    </button>
  )
}

function labelFor(status: DraftStatus, savedAt: Date | null): string {
  switch (status) {
    case "idle":
      return "Sincronizado"
    case "dirty":
      return "Rascunho pendente"
    case "saving":
      return "Salvando…"
    case "saved":
      return savedAt ? `Rascunho salvo ${savedAt.toLocaleTimeString()}` : "Rascunho salvo"
    case "error":
      return "Falha ao salvar — clique para tentar"
  }
}
