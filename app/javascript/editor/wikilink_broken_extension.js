import { RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin } from "@codemirror/view"

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const WIKILINK_RE = /\[\[([^\]|]+)\|([^\]]+)\]\]/g

const validationUpdated = StateEffect.define()
const brokenMark = Decoration.mark({ class: "wikilink-broken" })

const validationState = StateField.define({
  create() {
    return new Map()
  },
  update(value, transaction) {
    if (!transaction.docChanged && transaction.effects.length === 0) return value

    let nextValue = transaction.docChanged ? new Map() : value

    transaction.effects.forEach((effect) => {
      if (!effect.is(validationUpdated)) return
      if (nextValue === value) nextValue = new Map(value)
      nextValue.set(effect.value.uuid, effect.value.ok)
    })

    return nextValue
  }
})

class WikilinkBrokenPlugin {
  constructor(view) {
    this.view = view
    this.pending = new Set()
    this.decorations = buildDecorations(view.state.doc.toString(), view.state.field(validationState))
    this.queueValidation()
  }

  update(update) {
    const validationChanged = update.transactions.some((transaction) => {
      return transaction.effects.some((effect) => effect.is(validationUpdated))
    })

    if (!update.docChanged && !validationChanged) return

    this.decorations = buildDecorations(update.state.doc.toString(), update.state.field(validationState))
    this.queueValidation()
  }

  destroy() {
    this.pending.clear()
    this.view = null
  }

  queueValidation() {
    if (!this.view) return

    const cache = this.view.state.field(validationState)
    const uuids = extractResolvableUuids(this.view.state.doc.toString())

    uuids.forEach((uuid) => {
      if (cache.has(uuid) || this.pending.has(uuid)) return

      this.pending.add(uuid)
      this.checkUuid(uuid)
    })
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
        effects: validationUpdated.of({ uuid, ok: response.ok })
      })
    } catch (_) {
      if (!this.view) return
      this.view.dispatch({
        effects: validationUpdated.of({ uuid, ok: false })
      })
    } finally {
      this.pending.delete(uuid)
    }
  }
}

const wikilinkBrokenPlugin = ViewPlugin.fromClass(WikilinkBrokenPlugin, {
  decorations: (plugin) => plugin.decorations
})

export function wikilinkBrokenExtension() {
  return [validationState, wikilinkBrokenPlugin]
}

function buildDecorations(doc, validationCache) {
  const builder = new RangeSetBuilder()
  let match

  WIKILINK_RE.lastIndex = 0
  while ((match = WIKILINK_RE.exec(doc)) !== null) {
    const uuid = extractUuid((match[2] || "").trim())
    const broken = uuid ? validationCache.get(uuid) === false : true

    if (!broken) continue
    builder.add(match.index, match.index + match[0].length, brokenMark)
  }

  return builder.finish()
}

function extractResolvableUuids(doc) {
  const uuids = new Set()
  let match

  WIKILINK_RE.lastIndex = 0
  while ((match = WIKILINK_RE.exec(doc)) !== null) {
    const uuid = extractUuid((match[2] || "").trim())
    if (uuid) uuids.add(uuid)
  }

  return uuids
}

function extractUuid(payload) {
  const normalized = payload.replace(/^[a-z]+:/i, "").split("#")[0]
  return UUID_RE.test(normalized) ? normalized : null
}
