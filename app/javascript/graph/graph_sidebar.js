export function renderTagList(container, state, indexes, callbacks) {
  const focusedNodeId = state.ui.focusedNodeId
  const focusedNodeTags = focusedNodeId && state.graph.hasNode(focusedNodeId)
    ? new Set(state.graph.getNodeAttribute(focusedNodeId, "noteTags") || [])
    : null

  container.innerHTML = state.ui.activeTagsOrdered.map((tagId, index) => {
    const tag = indexes.tagMetaById.get(tagId)
    if (!tag) return ""

    const inTopN = state.ui.topN == null || index < state.ui.topN
    const attachedToFocusedNode = focusedNodeTags?.has(tagId) === true
    const focusActionLabel = attachedToFocusedNode ? "Remover" : "Adicionar"

    return `
      <div class="nm-graph__tag-row ${inTopN ? "is-highlighted" : ""} ${attachedToFocusedNode ? "is-attached" : ""}"
           draggable="true"
           tabindex="0"
           data-tag-id="${tag.id}"
           data-tag-index="${index}">
        <span class="nm-graph__tag-chip">
          <span class="nm-graph__tag-dot" style="background:${tag.color_hex || "#94a3b8"}"></span>
          ${escapeHtml(tag.name)}
        </span>
        <button type="button"
                class="nm-graph__tag-toggle ${attachedToFocusedNode ? "is-active" : ""} ${focusedNodeId ? "" : "is-disabled"}"
                ${focusedNodeId ? "" : "disabled"}
                draggable="false"
                data-tag-toggle="${tag.id}"
                aria-pressed="${attachedToFocusedNode ? "true" : "false"}">
          ${focusActionLabel}
        </button>
      </div>
    `
  }).join("")

  const dragState = {
    sourceTagId: null,
    targetTagId: null,
    placement: "before"
  }
  const clearDropTargets = () => {
    container.querySelectorAll(".nm-graph__tag-row").forEach((item) => {
      item.classList.remove("is-drop-before", "is-drop-after", "is-drop-target", "is-dragging")
    })
  }

  const resolveTargetRow = (event) => event.target.closest(".nm-graph__tag-row")

  container.addEventListener("dragstart", (event) => {
    const row = resolveTargetRow(event)
    if (!row) return

    dragState.sourceTagId = row.dataset.tagId
    setTimeout(() => {
      row.classList.add("is-dragging")
    }, 0)
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", dragState.sourceTagId)
  })

  container.addEventListener("dragover", (event) => {
    if (!dragState.sourceTagId) return

    event.preventDefault()
    const row = resolveTargetRow(event)
    if (!row || row.dataset.tagId === dragState.sourceTagId) return

    const rect = row.getBoundingClientRect()
    const placeAfter = event.clientY > rect.top + rect.height / 2
    dragState.targetTagId = row.dataset.tagId
    dragState.placement = placeAfter ? "after" : "before"

    clearDropTargets()
    row.classList.add("is-drop-target", placeAfter ? "is-drop-after" : "is-drop-before")
  })

  container.addEventListener("drop", (event) => {
    if (!dragState.sourceTagId || !dragState.targetTagId) return

    event.preventDefault()
    const sourceTagId = dragState.sourceTagId
    const targetTagId = dragState.targetTagId
    const placement = dragState.placement

    dragState.sourceTagId = null
    dragState.targetTagId = null
    dragState.placement = "before"
    clearDropTargets()

    if (sourceTagId === targetTagId) return
    callbacks.onReorder?.(sourceTagId, targetTagId, placement)
  })

  container.addEventListener("dragend", () => {
    dragState.sourceTagId = null
    dragState.targetTagId = null
    dragState.placement = "before"
    clearDropTargets()
  })

  container.querySelectorAll("[data-tag-id]").forEach((row) => {
    row.addEventListener("keydown", (event) => {
      if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
        event.preventDefault()
        callbacks.onShift?.(row.dataset.tagId, -1)
      } else if (event.key === "ArrowDown" || event.key === "ArrowRight") {
        event.preventDefault()
        callbacks.onShift?.(row.dataset.tagId, 1)
      }
    })
  })

  container.querySelectorAll("[data-tag-toggle]").forEach((button) => {
    button.addEventListener("pointerdown", (event) => {
      event.stopPropagation()
    })

    button.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      if (!focusedNodeId) return
      callbacks.onToggle?.(button.dataset.tagToggle)
    })
  })
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}
