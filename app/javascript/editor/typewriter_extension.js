import { RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin } from "@codemirror/view"

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

class TypewriterPlugin {
  constructor(view) {
    this.view = view
    this.pending = new Set()
    this.decorations = Decoration.none
    this.refresh()
    this.updatePadding()
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
    }

    if (selectingChanged && !isSelecting && enabled && !hasTextSelection && !update.view.composing) {
      setTimeout(() => maintainTypewriterScroll(update.view), 0)
    }
  }

  destroy() {
    if (!this.view) return
    this.view.scrollDOM.style.paddingBottom = ""
    this.view.dom.classList.remove("typewriter-mode")
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
      return
    }

    const padding = Math.round(this.view.scrollDOM.clientHeight * 0.5)
    this.view.scrollDOM.style.paddingBottom = `${padding}px`
    this.view.dom.classList.add("typewriter-mode")
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
        maxWidth: "100%",
        margin: "0",
        padding: "1rem 2rem"
      }
    })
  ]
}

export function toggleTypewriter(view, enabled) {
  view.dispatch({
    effects: setTypewriterModeEffect.of(!!enabled)
  })

  if (enabled) setTimeout(() => maintainTypewriterScroll(view), 0)
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
  const builder = new RangeSetBuilder()
  const fencedRanges = collectFencedRanges(doc)

  buildStructuralMarkdownDecorations(doc, selection, builder)
  buildInlineMarkdownDecorations(doc, selection, builder, fencedRanges)

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

    builder.add(link.from, link.displayFrom, hiddenSyntaxDecoration)
    builder.add(link.displayFrom, link.displayTo, Decoration.mark({
      class: displayClass,
      attributes: broken ? { title: "Nota nao encontrada" } : (link.promise ? { title: "Sugestao de nota futura" } : {})
    }))
    builder.add(link.displayTo, link.to, hiddenSyntaxDecoration)
  }

  return builder.finish()
}

function buildStructuralMarkdownDecorations(doc, selection, builder) {
  const lines = doc.split("\n")
  let offset = 0
  let inFence = false

  lines.forEach((line) => {
    if (/^\s*```/.test(line)) {
      addHiddenSyntaxRange(builder, offset, offset + line.length, selection)
      inFence = !inFence
      offset += line.length + 1
      return
    }

    if (inFence) {
      offset += line.length + 1
      return
    }

    const headingMatch = line.match(/^(\s{0,3}#{1,6}\s+)/)
    if (headingMatch) {
      addHiddenSyntaxRange(builder, offset, offset + headingMatch[1].length, selection)
    }

    const quoteMatch = line.match(/^(\s*>+\s?)/)
    if (quoteMatch) {
      addHiddenSyntaxRange(builder, offset, offset + quoteMatch[1].length, selection)
    }

    const listMatch = line.match(/^(\s*(?:[-*+]\s+|\d+\.\s+))/)
    if (listMatch) {
      addHiddenSyntaxRange(builder, offset, offset + listMatch[1].length, selection)
    }

    offset += line.length + 1
  })
}

function buildInlineMarkdownDecorations(doc, selection, builder, fencedRanges) {
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

      addHiddenSyntaxRange(builder, from, openTo, selection)
      if (closeFrom > openTo) {
        builder.add(openTo, closeFrom, Decoration.mark({
          tagName: "span",
          class: contentClass,
          attributes: { "data-typewriter-inline": contentClass }
        }))
      }
      addHiddenSyntaxRange(builder, closeFrom, to, selection)
    }
  })
}

function addHiddenSyntaxRange(builder, from, to, selection) {
  if (to <= from) return
  const overlapsSelection = rangesOverlap(from, to, selection.from, selection.to) ||
    (selection.empty && selection.head > from && selection.head < to)
  if (overlapsSelection) return
  builder.add(from, to, hiddenSyntaxDecoration)
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
    (selection.empty && selection.head > from && selection.head < to)
}
