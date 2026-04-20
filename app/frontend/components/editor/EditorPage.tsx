import { useParams } from "react-router-dom"

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

  const { payload } = state

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
          <p className="nm-editor-page__muted">
            {payload.note.slug}
            {payload.revision.updated_at ? ` · atualizado em ${payload.revision.updated_at}` : ""}
          </p>
        </header>
        <pre className="nm-editor-page__markdown">{payload.revision.content_markdown}</pre>
      </section>

      <section className="nm-editor-page__preview">
        <header>
          <h2>Preview</h2>
          <p className="nm-editor-page__muted">Renderização marked.js chega na próxima slice.</p>
        </header>
      </section>

      <aside className="nm-editor-page__properties">
        <header>
          <h2>Propriedades</h2>
          <p className="nm-editor-page__muted">
            {Object.keys(payload.properties).length === 0
              ? "Sem propriedades"
              : `${Object.keys(payload.properties).length} chave(s)`}
          </p>
        </header>
        <dl>
          {Object.entries(payload.properties).map(([key, value]) => (
            <div key={key} className="nm-editor-page__property">
              <dt>{key}</dt>
              <dd>{JSON.stringify(value)}</dd>
            </div>
          ))}
        </dl>
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
