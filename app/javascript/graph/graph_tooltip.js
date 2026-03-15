import { roleLabel } from "graph/graph_style"

export function renderTooltip(node, state, indexes, incidentEdges) {
  const tagNames = (node.noteTags || [])
    .map((tagId) => indexes.tagMetaById.get(tagId)?.name)
    .filter(Boolean)
    .slice(0, 5)

  const edgeSummaries = incidentEdges
    .slice(0, 4)
    .map((edge) => `${roleLabel(edge.hierRole)} · ${edge.otherTitle}`)

  return `
    <article class="nm-graph-tooltip ${node.id === state.ui.pinnedTooltipNodeId ? "is-pinned" : ""}">
      <p class="nm-graph-tooltip__eyebrow">${escapeHtml(node.slug)}</p>
      <h3>${escapeHtml(node.title || node.label)}</h3>
      <p class="nm-graph-tooltip__excerpt">${escapeHtml(node.excerpt || "Sem resumo inicial.")}</p>
      <p class="nm-graph-tooltip__tags">${escapeHtml(tagNames.join(" · ") || "Sem tags de nota")}</p>
      <div class="nm-graph-tooltip__links">
        ${edgeSummaries.map((item) => `<span>${escapeHtml(item)}</span>`).join("")}
      </div>
      <div class="nm-graph-tooltip__actions">
        <a href="/notes/${encodeURIComponent(node.slug)}">Abrir</a>
        <a href="/notes/${encodeURIComponent(node.slug)}/edit">Editar</a>
      </div>
    </article>
  `
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}
