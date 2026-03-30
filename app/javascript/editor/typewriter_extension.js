import { RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const RESOLVED_WIKILINK_RE = /\[\[([^\]|]+)\|(?:([a-z]+):)?([^\]]+)\]\]/gi
const PROMISE_WIKILINK_RE = /\[\[([^\]\|]+)\]\]/gi
const INLINE_PATTERNS = [
  { regex: /`([^`\n]+)`/g, delimiterLength: 1, contentClass: "typewriter-inline-code" },
  { regex: /~~([^~\n]+)~~/g, delimiterLength: 2, contentClass: "typewriter-inline-strike" },
  { regex: /\*\*([^*\n](?:.*?[^*\n])?)\*\*/g, delimiterLength: 2, contentClass: "typewriter-inline-strong" },
  { regex: /(?<!\*)\*(?=\S)([^*\n]*?\S)\*(?!\*)/g, delimiterLength: 1, contentClass: "typewriter-inline-emphasis" },
  { regex: /_([^_\n]+)_/g, delimiterLength: 1, contentClass: "typewriter-inline-emphasis" }
]
const ROLE_CLASS = {
  f: "wikilink-father",
  c: "wikilink-child",
  b: "wikilink-brother"
}

export const setTypewriterModeEffect = StateEffect.define()
export const setTypewriterSelectingEffect = StateEffect.define()
const validationUpdatedEffect = StateEffect.define()

const typewriterState = StateField.define({
  create() {
    return false
  },
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(setTypewriterModeEffect)) return !!effect.value
    }
    return value
  }
})

const selectingState = StateField.define({
  create() {
    return false
  },
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(setTypewriterSelectingEffect)) return !!effect.value
    }
    return value
  }
})

const validationState = StateField.define({
  create() {
    return new Map()
  },
  update(value, transaction) {
    if (!transaction.docChanged && transaction.effects.length === 0) return value

    let nextValue = transaction.docChanged ? new Map() : value
    for (const effect of transaction.effects) {
      if (!effect.is(validationUpdatedEffect)) continue
      if (nextValue === value) nextValue = new Map(value)
      nextValue.set(effect.value.uuid, effect.value.ok)
    }
    return nextValue
  }
})

const hiddenSyntaxDecoration = Decoration.replace({})

class ListMarkerWidget extends WidgetType {
  constructor(marker) {
    super()
    this.marker = marker
  }

  eq(other) {
    return other.marker === this.marker
  }

  toDOM() {
    const element = document.createElement("span")
    element.className = "typewriter-list-bullet"
    element.textContent = `${this.marker} `
    return element
  }
}

class TypewriterPlugin {
  constructor(view) {
    this.view = view
    this.pending = new Set()
    this.decorations = Decoration.none
    this._overlayAlignmentFrame = null
    this._domObserver = new MutationObserver(() => {
      this.applyRawTextMask()
    })
    this._domObserver.observe(this.view.dom, { childList: true, subtree: true })
    this.refresh()
    this.updatePadding()
    this.applyRawTextMask()
    this.scheduleOverlayAlignment()
  }

  update(update) {
    const modeChanged = update.transactions.some((transaction) => {
      return transaction.effects.some((effect) => effect.is(setTypewriterModeEffect))
    })
    const validationChanged = update.transactions.some((transaction) => {
      return transaction.effects.some((effect) => effect.is(validationUpdatedEffect))
    })
    const selectingChanged = update.transactions.some((transaction) => {
      return transaction.effects.some((effect) => effect.is(setTypewriterSelectingEffect))
    })

    if (update.docChanged || update.selectionSet || validationChanged || modeChanged) {
      this.refresh()
    }

    if (modeChanged || update.geometryChanged) this.updatePadding()
    if (update.docChanged || update.viewportChanged || modeChanged || update.selectionSet) this.applyRawTextMask()
    if (update.docChanged || update.selectionSet || update.geometryChanged || modeChanged || update.viewportChanged) {
      this.scheduleOverlayAlignment()
    }

    const enabled = update.state.field(typewriterState)
    const isSelecting = update.state.field(selectingState)
    const selection = update.state.selection.main
    const hasTextSelection = selection.anchor !== selection.head

    if (enabled && !isSelecting && !hasTextSelection && !update.view.composing && (update.selectionSet || update.docChanged || modeChanged)) {
      setTimeout(() => maintainTypewriterScroll(update.view), 0)
    }

    if (!enabled && modeChanged) {
      update.view.scrollDOM.style.paddingBottom = ""
      update.view.dom.classList.remove("typewriter-mode")
      this.clearRawTextMask()
      this.clearOverlayAlignment()
    }

    if (selectingChanged && !isSelecting && enabled && !hasTextSelection && !update.view.composing) {
      setTimeout(() => maintainTypewriterScroll(update.view), 0)
    }
  }

  destroy() {
    if (!this.view) return
    this.view.scrollDOM.style.paddingBottom = ""
    this.view.dom.classList.remove("typewriter-mode")
    this.clearRawTextMask()
    if (this._overlayAlignmentFrame) cancelAnimationFrame(this._overlayAlignmentFrame)
    this.clearOverlayAlignment()
    this._domObserver?.disconnect()
    this.pending.clear()
    this.view = null
  }

  refresh() {
    if (!this.view) return
    this.decorations = buildDecorations(this.view)
    this.queueValidation()
  }

  updatePadding() {
    if (!this.view) return
    if (!this.view.state.field(typewriterState)) {
      this.view.scrollDOM.style.paddingBottom = ""
      this.view.dom.classList.remove("typewriter-mode")
      this.clearRawTextMask()
      return
    }

    const padding = Math.round(this.view.scrollDOM.clientHeight * 0.5)
    this.view.scrollDOM.style.paddingBottom = `${padding}px`
    this.view.dom.classList.add("typewriter-mode")
  }

  applyRawTextMask() {
    if (!this.view) return

    const enabled = this.view.state.field(typewriterState)
    const contentDOM = this.view.contentDOM
    if (!enabled) {
      this.clearRawTextMask()
      return
    }

    if (contentDOM) {
      contentDOM.style.color = "transparent"
      contentDOM.style.webkitTextFillColor = "transparent"
      contentDOM.style.opacity = "0"
    }

    this.view.dom.querySelectorAll(".cm-content").forEach((content) => {
      content.style.color = "transparent"
      content.style.webkitTextFillColor = "transparent"
      content.style.opacity = "0"
    })

    this.view.dom.querySelectorAll(".cm-line").forEach((line) => {
      line.style.color = "transparent"
      line.style.webkitTextFillColor = "transparent"
      line.style.visibility = "hidden"
    })
  }

  clearRawTextMask() {
    if (!this.view) return

    const contentDOM = this.view.contentDOM
    if (contentDOM) {
      contentDOM.style.removeProperty("color")
      contentDOM.style.removeProperty("-webkit-text-fill-color")
      contentDOM.style.removeProperty("opacity")
    }

    this.view.dom.querySelectorAll(".cm-content").forEach((content) => {
      content.style.removeProperty("color")
      content.style.removeProperty("-webkit-text-fill-color")
      content.style.removeProperty("opacity")
    })

    this.view.dom.querySelectorAll(".cm-line").forEach((line) => {
      line.style.removeProperty("color")
      line.style.removeProperty("-webkit-text-fill-color")
      line.style.removeProperty("visibility")
    })
  }

  updateOverlayAlignment() {
    if (!this.view) return

    const enabled = this.view.state.field(typewriterState)
    if (!enabled) {
      this.clearOverlayAlignment()
      return
    }

    const firstLine = this.view.dom.querySelector(".cm-line")
    const previewAnchor = document.querySelector("#preview-pane .preview-prose h1, #preview-pane .preview-prose h2, #preview-pane .preview-prose h3, #preview-pane .preview-prose h4, #preview-pane .preview-prose p, #preview-pane .preview-prose li, #preview-pane .preview-prose blockquote, #preview-pane .preview-prose pre")
    if (!firstLine || !previewAnchor) {
      this.clearOverlayAlignment()
      return
    }

    const lineRect = firstLine.getBoundingClientRect()
    const previewRect = previewAnchor.getBoundingClientRect()
    if (!lineRect || !previewRect) {
      this.clearOverlayAlignment()
      return
    }

    const dx = Math.round((previewRect.left - lineRect.left) * 100) / 100
    const dy = Math.round((previewRect.top - lineRect.top) * 100) / 100

    this.view.dom.querySelectorAll(".cm-cursorLayer, .cm-selectionLayer").forEach((layer) => {
      layer.style.setProperty("transform", `translate(${dx}px, ${dy}px)`)
    })
  }

  clearOverlayAlignment() {
    if (!this.view) return
    this.view.dom.querySelectorAll(".cm-cursorLayer, .cm-selectionLayer").forEach((layer) => {
      layer.style.removeProperty("transform")
    })
  }

  scheduleOverlayAlignment() {
    if (!this.view) return
    if (this._overlayAlignmentFrame) cancelAnimationFrame(this._overlayAlignmentFrame)
    this._overlayAlignmentFrame = requestAnimationFrame(() => {
      this._overlayAlignmentFrame = null
      this.updateOverlayAlignment()
    })
  }

  queueValidation() {
    if (!this.view || !this.view.state.field(typewriterState)) return

    const cache = this.view.state.field(validationState)
    for (const link of extractWikilinks(this.view.state.doc.toString())) {
      if (!link.uuid || cache.has(link.uuid) || this.pending.has(link.uuid)) continue
      this.pending.add(link.uuid)
      this.checkUuid(link.uuid)
    }
  }

  async checkUuid(uuid) {
    try {
      const response = await fetch(`/notes/${uuid}`, {
        method: "GET",
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })

      if (!this.view) return
      this.view.dispatch({
        effects: validationUpdatedEffect.of({ uuid, ok: response.ok })
      })
    } catch (_) {
      if (!this.view) return
      this.view.dispatch({
        effects: validationUpdatedEffect.of({ uuid, ok: false })
      })
    } finally {
      this.pending.delete(uuid)
    }
  }
}

const typewriterPlugin = ViewPlugin.fromClass(TypewriterPlugin, {
  decorations: (plugin) => plugin.decorations
})

export function createTypewriterExtension(enabled = false) {
  return [
    typewriterState.init(() => enabled),
    selectingState,
    validationState,
    typewriterPlugin,
    EditorView.theme({
      "&.typewriter-mode .cm-content": {
        maxWidth: "none",
        margin: "0",
        padding: "0"
      }
    })
  ]
}

export function toggleTypewriter(view, enabled) {
  view.dispatch({
    effects: setTypewriterModeEffect.of(!!enabled)
  })

  if (enabled) {
    setTimeout(() => {
      const head = view.state.selection.main.head
      view.dispatch({
        selection: { anchor: head, head },
        scrollIntoView: true
      })
      maintainTypewriterScroll(view)
    }, 0)
  }
}

export function setTypewriterSelecting(view, selecting) {
  view.dispatch({
    effects: setTypewriterSelectingEffect.of(!!selecting)
  })
}

export function isTypewriterEnabled(view) {
  return !!view?.state.field(typewriterState)
}

export function getTypewriterSyncData(view) {
  if (!view) return null
  const cursorPos = view.state.selection.main.head
  const doc = view.state.doc
  const currentLine = doc.lineAt(cursorPos).number
  return { currentLine, totalLines: doc.lines }
}

export function maintainTypewriterScroll(view) {
  const targetScroll = calculateTypewriterScroll(view)
  if (targetScroll == null) return

  const currentScroll = view.scrollDOM.scrollTop
  if (Math.abs(currentScroll - targetScroll) > 5) {
    view.scrollDOM.scrollTop = targetScroll
  }
}

function calculateTypewriterScroll(view) {
  try {
    if (!view.state.field(typewriterState)) return null
    const selection = view.state.selection.main
    if (selection.anchor !== selection.head) return null

    const coords = view.coordsAtPos(selection.head)
    if (!coords) return null

    const editorRect = view.dom.getBoundingClientRect()
    const scrollDOM = view.scrollDOM
    const cursorY = coords.top - editorRect.top + scrollDOM.scrollTop
    const targetY = scrollDOM.clientHeight * 0.5
    const maxScroll = scrollDOM.scrollHeight - scrollDOM.clientHeight
    return Math.max(0, Math.min(cursorY - targetY, maxScroll))
  } catch (_) {
    return null
  }
}

function buildDecorations(view) {
  const enabled = view.state.field(typewriterState)
  if (!enabled) return Decoration.none

  const doc = view.state.doc.toString()
  const selection = view.state.selection.main
  const validationCache = view.state.field(validationState)
  const decorations = []
  const builder = new RangeSetBuilder()
  const fencedRanges = collectFencedRanges(doc)

  buildStructuralMarkdownDecorations(doc, selection, decorations)
  buildInlineMarkdownDecorations(doc, selection, decorations, fencedRanges)

  for (const link of extractWikilinks(doc)) {
    const overlapsSelection = rangesOverlap(link.from, link.to, selection.from, selection.to) ||
      (selection.empty && selection.head > link.from && selection.head < link.to)
    if (overlapsSelection) continue

    const broken = link.promise ? false : (!link.uuid || validationCache.get(link.uuid) === false)
    const displayClass = link.promise
      ? "wikilink-promise"
      : broken
        ? "wikilink-broken"
        : `wikilink ${ROLE_CLASS[link.role] || "wikilink-null"}`
    const attributes = broken
      ? { title: "Nota nao encontrada" }
      : (link.promise
        ? { title: "Sugestao de nota futura" }
        : {
            title: "Ctrl/Cmd+click para abrir a nota",
            "data-note-href": `/notes/${link.uuid}`,
            "data-typewriter-wikilink": "true"
          })

    queueDecoration(decorations, link.from, link.displayFrom, hiddenSyntaxDecoration)
    queueDecoration(decorations, link.displayFrom, link.displayTo, Decoration.mark({
      class: displayClass,
      attributes
    }))
    queueDecoration(decorations, link.displayTo, link.to, hiddenSyntaxDecoration)
  }

  decorations
    .sort((a, b) => {
      if (a.from !== b.from) return a.from - b.from
      if (a.decoration.startSide !== b.decoration.startSide) return a.decoration.startSide - b.decoration.startSide
      return a.to - b.to
    })
    .forEach(({ from, to, decoration }) => builder.add(from, to, decoration))

  return builder.finish()
}

function buildStructuralMarkdownDecorations(doc, selection, decorations) {
  const lines = doc.split("\n")
  let offset = 0
  let inFence = false

  lines.forEach((line) => {
    if (/^\s*```/.test(line)) {
      addHiddenSyntaxRange(decorations, offset, offset + line.length, selection)
      inFence = !inFence
      offset += line.length + 1
      return
    }

    if (inFence) {
      addVisibleContentMark(decorations, offset, offset + line.length, "typewriter-block-code")
      offset += line.length + 1
      return
    }

    const headingMatch = line.match(/^(\s{0,3}#{1,6}\s+)/)
    if (headingMatch) {
      const contentFrom = offset + headingMatch[1].length
      addHiddenSyntaxRange(decorations, offset, contentFrom, selection)
      addVisibleContentMark(decorations, contentFrom, offset + line.length, `typewriter-block-heading typewriter-block-heading-${headingMatch[1].trim().length}`)
    }

    const quoteMatch = line.match(/^(\s*>+\s?)/)
    if (quoteMatch) {
      const contentFrom = offset + quoteMatch[1].length
      addHiddenSyntaxRange(decorations, offset, contentFrom, selection)
      addVisibleContentMark(decorations, contentFrom, offset + line.length, "typewriter-block-quote")
    }

    const listMatch = line.match(/^(\s*(?:[-*+]\s+|\d+\.\s+))/)
    if (listMatch) {
      const contentFrom = offset + listMatch[1].length
      const marker = extractListMarker(listMatch[1])
      addListMarkerDecoration(decorations, offset, contentFrom, selection, marker)
      addVisibleContentMark(decorations, contentFrom, offset + line.length, "typewriter-block-list")
    }

    offset += line.length + 1
  })
}

function buildInlineMarkdownDecorations(doc, selection, decorations, fencedRanges) {
  INLINE_PATTERNS.forEach(({ regex, delimiterLength, contentClass }) => {
    regex.lastIndex = 0
    let match

    while ((match = regex.exec(doc)) !== null) {
      const full = match[0]
      const from = match.index
      const to = from + full.length
      if (rangeOverlapsAny(from, to, fencedRanges)) continue
      if (selectionTouchesRange(selection, from, to)) continue
      const openTo = from + delimiterLength
      const closeFrom = to - delimiterLength

      addHiddenSyntaxRange(decorations, from, openTo, selection)
      if (closeFrom > openTo) {
        queueDecoration(decorations, openTo, closeFrom, Decoration.mark({
          tagName: "span",
          class: contentClass,
          attributes: { "data-typewriter-inline": contentClass }
        }))
      }
      addHiddenSyntaxRange(decorations, closeFrom, to, selection)
    }
  })
}

function addHiddenSyntaxRange(decorations, from, to, selection) {
  if (to <= from) return
  const overlapsSelection = rangesOverlap(from, to, selection.from, selection.to) ||
    cursorTouchesRange(selection, from, to)
  if (overlapsSelection) return
  queueDecoration(decorations, from, to, hiddenSyntaxDecoration)
}

function addListMarkerDecoration(decorations, from, to, selection, marker) {
  if (to <= from) return
  const overlapsSelection = rangesOverlap(from, to, selection.from, selection.to) ||
    cursorTouchesRange(selection, from, to)
  if (overlapsSelection) return
  queueDecoration(decorations, from, to, Decoration.replace({
    widget: new ListMarkerWidget(marker),
    inclusive: false
  }))
}

function addVisibleContentMark(decorations, from, to, className) {
  if (to <= from) return
  queueDecoration(decorations, from, to, Decoration.mark({
    tagName: "span",
    class: className
  }))
}

function queueDecoration(decorations, from, to, decoration) {
  if (to <= from) return
  decorations.push({ from, to, decoration })
}

function collectFencedRanges(doc) {
  const ranges = []
  const lines = doc.split("\n")
  let offset = 0
  let activeRangeStart = null

  lines.forEach((line) => {
    if (/^\s*```/.test(line)) {
      if (activeRangeStart == null) {
        activeRangeStart = offset
      } else {
        ranges.push({ from: activeRangeStart, to: offset + line.length })
        activeRangeStart = null
      }
    }

    offset += line.length + 1
  })

  if (activeRangeStart != null) {
    ranges.push({ from: activeRangeStart, to: doc.length })
  }

  return ranges
}

function extractWikilinks(doc) {
  const links = []
  let match

  RESOLVED_WIKILINK_RE.lastIndex = 0
  while ((match = RESOLVED_WIKILINK_RE.exec(doc)) !== null) {
    const payload = (match[3] || "").trim()
    const normalizedUuid = payload.replace(/^[a-z]+:/i, "").toLowerCase()
    links.push({
      from: match.index,
      to: match.index + match[0].length,
      displayFrom: match.index + 2,
      displayTo: match.index + match[0].indexOf("|"),
      display: (match[1] || "").trim(),
      role: match[2] ? match[2].toLowerCase() : null,
      uuid: UUID_RE.test(normalizedUuid) ? normalizedUuid : null,
      promise: false
    })
  }

  PROMISE_WIKILINK_RE.lastIndex = 0
  while ((match = PROMISE_WIKILINK_RE.exec(doc)) !== null) {
    if (doc.slice(match.index, match.index + match[0].length).includes("|")) continue
    links.push({
      from: match.index,
      to: match.index + match[0].length,
      displayFrom: match.index + 2,
      displayTo: match.index + match[0].length - 2,
      display: (match[1] || "").trim(),
      role: null,
      uuid: null,
      promise: true
    })
  }

  return links.sort((left, right) => left.from - right.from)
}

function rangesOverlap(fromA, toA, fromB, toB) {
  return fromA < toB && fromB < toA
}

function rangeOverlapsAny(from, to, ranges) {
  return ranges.some((range) => rangesOverlap(from, to, range.from, range.to))
}

function selectionTouchesRange(selection, from, to) {
  return rangesOverlap(from, to, selection.from, selection.to) ||
    cursorTouchesRange(selection, from, to)
}

function cursorTouchesRange(selection, from, to) {
  if (!selection.empty) return false
  return selection.head >= from && selection.head <= to
}

function extractListMarker(prefix) {
  const orderedMatch = prefix.match(/(\d+\.)/)
  if (orderedMatch) return orderedMatch[1]
  return "•"
}
