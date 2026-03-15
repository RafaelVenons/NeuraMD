export function renderTagList(container, state, indexes, onMove) {
  container.innerHTML = state.ui.activeTagsOrdered.map((tagId, index) => {
    const tag = indexes.tagMetaById.get(tagId)
    if (!tag) return ""

    const inTopN = index < state.ui.topN
    return `
      <div class="nm-graph__tag-row ${inTopN ? "is-highlighted" : ""}">
        <span class="nm-graph__tag-chip">
          <span class="nm-graph__tag-dot" style="background:${tag.color_hex || "#94a3b8"}"></span>
          ${escapeHtml(tag.name)}
        </span>
        <span class="nm-graph__tag-actions">
          <button type="button" data-tag-move="${tag.id}:-1">↑</button>
          <button type="button" data-tag-move="${tag.id}:1">↓</button>
        </span>
      </div>
    `
  }).join("")

  container.querySelectorAll("[data-tag-move]").forEach((button) => {
    button.addEventListener("click", () => {
      const [tagId, delta] = button.dataset.tagMove.split(":")
      onMove(tagId, Number(delta))
    })
  })
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}
