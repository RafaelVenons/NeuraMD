export function renderTagList(container, state, indexes, callbacks) {
  const focusedNodeId = state.ui.focusedNodeId
  const focusedNodeTags = focusedNodeId && state.graph.hasNode(focusedNodeId)
    ? new Set((state.graph.getNodeAttribute(focusedNodeId, "noteTags") || []).map(String))
    : null

  container.innerHTML = state.ui.activeTagsOrdered.map((tagId, index) => {
    const tag = indexes.tagMetaById.get(tagId)
    if (!tag) return ""
    const tagKey = String(tag.id)

    const inTopN = state.ui.topN == null || index < state.ui.topN
    const attachedToFocusedNode = focusedNodeTags?.has(tagKey) === true

    return `
      <div class="nm-graph__tag-row ${inTopN ? "is-highlighted" : ""} ${attachedToFocusedNode ? "is-attached" : ""}"
           draggable="true"
           tabindex="0"
           role="button"
           aria-pressed="${attachedToFocusedNode ? "true" : "false"}"
           data-tag-id="${tagKey}"
           data-tag-index="${index}">
        <span class="nm-graph__tag-chip">
          <span class="nm-graph__tag-dot" style="background:${tag.color_hex || "#94a3b8"}"></span>
          <span style="color:${tag.color_hex || "#94a3b8"}">${escapeHtml(tag.name)}</span>
        </span>
      </div>
    `
  }).join("")

  const dragState = {
    sourceTagId: null,
    targetTagId: null,
    placement: "before",
    suppressClickUntil: 0
  }
  const ensureGapElement = () => {
    let gap = container.querySelector(".nm-graph__tag-gap")
    if (!gap) {
      gap = document.createElement("div")
      gap.className = "nm-graph__tag-gap"
    }
    return gap
  }
  const clearGap = () => {
    container.querySelector(".nm-graph__tag-gap")?.remove()
  }
  const clearDropTargets = () => {
    container.querySelectorAll(".nm-graph__tag-row").forEach((item) => {
      item.classList.remove("is-dragging")
    })
    clearGap()
  }

  const allRows = () => [...container.querySelectorAll(".nm-graph__tag-row")]
  const resolveTargetRow = (event) => {
    const directRow = event.target.closest(".nm-graph__tag-row")
    if (directRow && directRow.dataset.tagId !== dragState.sourceTagId) return directRow
    return null
  }
  const resolveBoundaryTarget = (event) => {
    const rows = allRows().filter((row) => row.dataset.tagId !== dragState.sourceTagId)
    if (!rows.length) return null

    const firstRow = rows[0]
    const lastRow = rows[rows.length - 1]
    const containerRect = container.getBoundingClientRect()
    const firstRect = firstRow.getBoundingClientRect()
    const lastRect = lastRow.getBoundingClientRect()
    const generousTopZone = firstRect.top + Math.max(24, firstRect.height * 0.75)
    const generousBottomZone = lastRect.bottom - Math.max(24, lastRect.height * 0.75)

    if (event.clientY >= containerRect.top && event.clientY <= generousTopZone) {
      return { row: firstRow, placement: "before" }
    }
    if (event.clientY >= generousBottomZone && event.clientY <= containerRect.bottom) {
      return { row: lastRow, placement: "after" }
    }
    return null
  }

  container.addEventListener("dragstart", (event) => {
    const row = resolveTargetRow(event)
    if (!row) return

    dragState.sourceTagId = row.dataset.tagId
    dragState.targetTagId = null
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
    const boundaryTarget = row ? null : resolveBoundaryTarget(event)
    const targetRow = row || boundaryTarget?.row
    const placement = boundaryTarget?.placement

    if (!targetRow || targetRow.dataset.tagId === dragState.sourceTagId) {
      dragState.targetTagId = null
      return
    }

    const rect = targetRow.getBoundingClientRect()
    const placeAfter = placement ? placement === "after" : event.clientY > rect.top + rect.height / 2
    dragState.targetTagId = targetRow.dataset.tagId
    dragState.placement = placeAfter ? "after" : "before"

    const gap = ensureGapElement()
    if (placeAfter) targetRow.insertAdjacentElement("afterend", gap)
    else targetRow.insertAdjacentElement("beforebegin", gap)
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
    dragState.suppressClickUntil = Date.now() + 220
    clearDropTargets()

    if (sourceTagId === targetTagId) return
    callbacks.onReorder?.(sourceTagId, targetTagId, placement)
  })

  container.addEventListener("dragend", () => {
    dragState.suppressClickUntil = Date.now() + 220
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
      } else if (event.key === "Enter" || event.key === " ") {
        event.preventDefault()
        if (!focusedNodeId) return
        callbacks.onToggle?.(row.dataset.tagId)
      }
    })

    row.addEventListener("click", (event) => {
      event.preventDefault()
      if (Date.now() < dragState.suppressClickUntil) return
      if (!focusedNodeId) return
      callbacks.onToggle?.(row.dataset.tagId)
    })
  })
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}
