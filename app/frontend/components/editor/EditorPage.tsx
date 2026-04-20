import { useEffect, useState } from "react"
import { useParams } from "react-router-dom"

import { AiReviewPanel } from "~/components/editor/AiReviewPanel"
import { EditorPane } from "~/components/editor/EditorPane"
import { PreviewPane } from "~/components/editor/PreviewPane"
import { PropertiesEditor } from "~/components/editor/PropertiesEditor"
import { RevisionsPanel } from "~/components/editor/RevisionsPanel"
import { TagSidebar } from "~/components/editor/TagSidebar"
import { TtsPlayer } from "~/components/editor/TtsPlayer"
import type { NotePayload } from "~/components/editor/types"
import { useDraftAutosave, type DraftStatus } from "~/components/editor/useDraftAutosave"
import { useNotePayload } from "~/components/editor/useNotePayload"
import { fetchJson } from "~/runtime/fetchJson"

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

  return (
    <EditorLoaded
      key={slug}
      slug={slug}
      initialContent={state.payload.revision.content_markdown}
      payload={state.payload}
      reload={state.reload}
    />
  )
}

type CheckpointStatus = "idle" | "saving" | "saved" | "error"

function EditorLoaded({
  slug,
  initialContent,
  payload,
  reload,
}: {
  slug: string
  initialContent: string
  payload: NotePayload
  reload: () => void
}) {
  const [content, setContent] = useState(initialContent)
  const { status, savedAt, flushNow, cancelPending, markSynced } = useDraftAutosave({ slug, content })
  const [checkpointStatus, setCheckpointStatus] = useState<CheckpointStatus>("idle")
  const [checkpointError, setCheckpointError] = useState<string | null>(null)
  const [revisionsToken, setRevisionsToken] = useState(0)

  useEffect(() => {
    setContent(initialContent)
  }, [initialContent])

  const runCheckpoint = async () => {
    setCheckpointStatus("saving")
    setCheckpointError(null)
    try {
      // Cancel the pending debounce and let any in-flight draft settle first,
      // so we can't race a stale draft POST with the checkpoint.
      cancelPending()
      await flushNow()
      const snapshot = content
      await fetchJson(`/api/notes/${encodeURIComponent(slug)}/checkpoint`, {
        method: "POST",
        body: { content_markdown: snapshot },
      })
      markSynced(snapshot)
      setCheckpointStatus("saved")
      setRevisionsToken((t) => t + 1)
    } catch (error) {
      setCheckpointStatus("error")
      setCheckpointError(error instanceof Error ? error.message : "Erro ao criar checkpoint")
    }
  }

  const handleRestored = () => {
    reload()
    setRevisionsToken((t) => t + 1)
  }

  return (
    <div className="nm-editor-page">
      <aside className="nm-editor-page__tags">
        <TagSidebar slug={slug} initialTags={payload.tags} />
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
            <CheckpointButton
              status={checkpointStatus}
              error={checkpointError}
              onClick={runCheckpoint}
            />
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
          key={payload.revision.id ?? "no-revision"}
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
        <RevisionsPanel slug={slug} onRestored={handleRestored} refreshToken={revisionsToken} />
        <AiReviewPanel slug={slug} />
      </aside>
      <TtsPlayer slug={slug} noteTitle={payload.note.title} />
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

function CheckpointButton({
  status,
  error,
  onClick,
}: {
  status: CheckpointStatus
  error: string | null
  onClick: () => void
}) {
  const label =
    status === "saving"
      ? "Criando…"
      : status === "saved"
        ? "Checkpoint criado"
        : status === "error"
          ? "Tentar novamente"
          : "Criar checkpoint"
  return (
    <button
      type="button"
      className={`nm-editor-page__checkpoint-btn nm-editor-page__checkpoint-btn--${status}`}
      onClick={onClick}
      disabled={status === "saving"}
      title={status === "error" && error ? error : "Cria revisão permanente com o conteúdo atual"}
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
