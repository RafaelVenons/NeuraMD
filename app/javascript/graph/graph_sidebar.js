export function renderTagList(container, state, indexes, callbacks) {
  const focusedNodeId = state.ui.focusedNodeId
  const focusedNodeTags = focusedNodeId && state.graph.hasNode(focusedNodeId)
    ? new Set((state.graph.getNodeAttribute(focusedNodeId, "noteTags") || []).map(String))
    : null
  const searchQuery = (state.ui.tagSearchQuery || "").trim()
  const tagIds = searchQuery
    ? rankTagIdsBySearch(state.ui.activeTagsOrdered, indexes, searchQuery)
    : state.ui.activeTagsOrdered

  container.innerHTML = tagIds.map((tagId, index) => {
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

function rankTagIdsBySearch(tagIds, indexes, query) {
  const normalizedQuery = normalizeSearchText(query)
  if (!normalizedQuery) return tagIds

  const queryVector = trigramVector(normalizedQuery)

  return tagIds
    .map((tagId, index) => {
      const tag = indexes.tagMetaById.get(tagId)
      if (!tag) return null

      const normalizedName = normalizeSearchText(tag.name)
      if (!normalizedName) return null

      const score = normalizedName.includes(normalizedQuery)
        ? 1
        : cosineSimilarity(trigramVector(normalizedName), queryVector)

      if (score <= 0) return null
      return { tagId, index, score }
    })
    .filter(Boolean)
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ tagId }) => tagId)
}

function normalizeSearchText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

function trigramVector(value) {
  const compact = `  ${value.replace(/\s+/g, " ")}  `
  const vector = new Map()

  for (let index = 0; index <= compact.length - 3; index += 1) {
    const gram = compact.slice(index, index + 3)
    vector.set(gram, (vector.get(gram) || 0) + 1)
  }

  return vector
}

function cosineSimilarity(left, right) {
  let dot = 0
  let leftNorm = 0
  let rightNorm = 0

  left.forEach((value, key) => {
    leftNorm += value * value
    dot += value * (right.get(key) || 0)
  })

  right.forEach((value) => {
    rightNorm += value * value
  })

  if (!leftNorm || !rightNorm) return 0
  return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm))
}

export function renderNoteCollections(targets, state, callbacks = {}) {
  renderLinklessList(targets.linklessList, state, callbacks)
  renderPromiseList(targets.promiseList, state, callbacks)
}

function renderLinklessList(container, state, callbacks) {
  if (!container) return

  const notes = collectVisibleNotes(state)
    .filter((note) => !note.hasLinks)
    .sort((a, b) => compareDatesDesc(a.updatedAt, b.updatedAt) || a.title.localeCompare(b.title, "pt-BR"))

  renderNoteList(container, notes, {
    emptyText: "Nenhuma nota sem links.",
    onSelectNote: callbacks.onSelectNote
  })
}

function renderPromiseList(container, state, callbacks) {
  if (!container) return

  const notes = collectVisibleNotes(state)
    .filter((note) => note.hasPromises)
    .flatMap((note) => note.promiseTitles.map((promiseTitle) => ({
      id: note.id,
      title: promiseTitle,
      sourceTitle: note.title,
      updatedAt: note.updatedAt
    })))
    .sort((a, b) => compareDatesDesc(a.updatedAt, b.updatedAt) || a.title.localeCompare(b.title, "pt-BR"))

  container.innerHTML = notes.length
    ? notes.map((note) => `
      <button type="button" class="nm-graph__note-row" data-promise-title="${escapeHtmlAttribute(note.title)}">
        <span class="nm-graph__note-title">${escapeHtml(note.title)}</span>
        <span class="nm-graph__note-meta">${escapeHtml(note.sourceTitle)} · ${escapeHtml(formatDate(note.updatedAt))}</span>
      </button>
    `).join("")
    : `<p class="nm-graph__list-empty">Nenhuma sugestao pendente.</p>`

  bindPromiseCreation(container, callbacks.onCreatePromise)
}

function renderNoteList(container, notes, options) {
  container.innerHTML = notes.length
    ? notes.map((note) => `
      <button type="button" class="nm-graph__note-row" data-note-id="${note.id}">
        <span class="nm-graph__note-title">${escapeHtml(note.title)}</span>
        <span class="nm-graph__note-meta">${escapeHtml(formatDate(note.updatedAt))}</span>
      </button>
    `).join("")
    : `<p class="nm-graph__list-empty">${options.emptyText}</p>`

  bindNoteSelection(container, options.onSelectNote)
}

function bindNoteSelection(container, onSelectNote) {
  if (!onSelectNote) return

  container.querySelectorAll("[data-note-id]").forEach((row) => {
    row.addEventListener("click", () => {
      onSelectNote(row.dataset.noteId)
    })
  })
}

function bindPromiseCreation(container, onCreatePromise) {
  if (!onCreatePromise) return

  container.querySelectorAll("[data-promise-title]").forEach((row) => {
    row.addEventListener("click", () => {
      onCreatePromise(row.dataset.promiseTitle)
    })
  })
}

function collectVisibleNotes(state) {
  const notes = []

  state.graph.forEachNode((nodeId, attributes) => {
    const display = state.display.nodes.get(nodeId)
    if (display?.hidden) return

    notes.push({
      id: nodeId,
      title: attributes.title || attributes.label || nodeId,
      updatedAt: attributes.updatedAt || attributes.createdAt || null,
      hasLinks: attributes.hasLinks === true,
      hasPromises: attributes.hasPromises === true,
      promiseCount: attributes.promiseCount || 0,
      promiseTitles: attributes.promiseTitles || []
    })
  })

  return notes
}

function escapeHtml(value) {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

function escapeHtmlAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;")
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

function compareDatesDesc(left, right) {
  const leftTime = left ? new Date(left).getTime() : 0
  const rightTime = right ? new Date(right).getTime() : 0

  return rightTime - leftTime
}
