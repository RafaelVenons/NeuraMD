export function renderTooltip(node, state) {
  const metaParts = [formatDate(node.updatedAt || node.createdAt)].filter(Boolean)
  const excerpt = truncate(node.excerpt || "Sem resumo inicial.", 180)

  const propertiesHtml = renderProperties(node.properties)

  return `
    <a class="nm-graph-tooltip ${node.id === state.ui.pinnedTooltipNodeId ? "is-pinned" : ""}"
       href="/notes/${encodeURIComponent(node.slug)}"
       data-turbo-prefetch="false">
      <h3 class="nm-graph-tooltip__title">${escapeHtml(node.title || node.label)}</h3>
      <p class="nm-graph-tooltip__meta">${escapeHtml(metaParts.join(" · "))}</p>
      ${propertiesHtml}
      <p class="nm-graph-tooltip__excerpt">${escapeHtml(excerpt)}</p>
    </a>
  `
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function formatDate(value) {
  if (!value) return ""

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""

  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  }).format(date)
}

function renderProperties(properties) {
  if (!properties || typeof properties !== "object") return ""

  const entries = Object.entries(properties).filter(([, v]) => v !== null && v !== "")
  if (entries.length === 0) return ""

  const items = entries
    .map(([key, value]) => `<span class="nm-graph-tooltip__prop">${escapeHtml(key)}: ${escapeHtml(String(value))}</span>`)
    .join(" ")

  return `<p class="nm-graph-tooltip__properties">${items}</p>`
}

function truncate(value, limit) {
  if (!value || value.length <= limit) return value
  return `${value.slice(0, limit - 1).trimEnd()}…`
}
