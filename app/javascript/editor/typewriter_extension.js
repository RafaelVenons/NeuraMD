import { StateEffect, StateField } from "@codemirror/state"
import { EditorView, ViewPlugin } from "@codemirror/view"

export const setTypewriterModeEffect = StateEffect.define()
export const setTypewriterSelectingEffect = StateEffect.define()

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

function calculateTypewriterScroll(view) {
  try {
    if (!view?.state.field(typewriterState)) return null

    const cursorPos = view.state.selection.main.head
    const coords = view.coordsAtPos(cursorPos)
    if (!coords) return null

    const editorRect = view.dom.getBoundingClientRect()
    const scrollDOM = view.scrollDOM
    const cursorY = coords.top - editorRect.top + scrollDOM.scrollTop
    const viewportCenter = scrollDOM.clientHeight / 2
    const targetScroll = cursorY - viewportCenter
    const maxScroll = scrollDOM.scrollHeight - scrollDOM.clientHeight

    return Math.max(0, Math.min(targetScroll, maxScroll))
  } catch {
    return null
  }
}

export function maintainTypewriterScroll(view) {
  const targetScroll = calculateTypewriterScroll(view)
  if (targetScroll == null) return

  const currentScroll = view.scrollDOM.scrollTop
  if (Math.abs(currentScroll - targetScroll) > 5) {
    view.scrollDOM.scrollTop = targetScroll
  }
}

class TypewriterPlugin {
  constructor(view) {
    this.view = view
    this.updatePadding()
  }

  update(update) {
    const modeChanged = update.transactions.some((transaction) => {
      return transaction.effects.some((effect) => effect.is(setTypewriterModeEffect))
    })

    if (modeChanged || update.geometryChanged) {
      this.updatePadding()
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
    }
  }

  updatePadding() {
    const enabled = this.view.state.field(typewriterState)
    const scroller = this.view.scrollDOM

    if (enabled) {
      scroller.style.paddingBottom = `${Math.round(scroller.clientHeight * 0.5)}px`
      this.view.dom.classList.add("typewriter-mode")
      return
    }

    scroller.style.paddingBottom = ""
    this.view.dom.classList.remove("typewriter-mode")
  }

  destroy() {
    this.view.scrollDOM.style.paddingBottom = ""
    this.view.dom.classList.remove("typewriter-mode")
  }
}

const typewriterPlugin = ViewPlugin.fromClass(TypewriterPlugin)

export function createTypewriterExtension(enabled = false) {
  return [
    typewriterState.init(() => enabled),
    selectingState,
    typewriterPlugin,
    EditorView.theme({
      "&.typewriter-mode .cm-content": {},
      "&.typewriter-mode .cm-cursor": {}
    })
  ]
}

export function toggleTypewriter(view, enabled) {
  view.dispatch({
    effects: setTypewriterModeEffect.of(enabled)
  })

  if (enabled) {
    setTimeout(() => maintainTypewriterScroll(view), 0)
  }
}

export function isTypewriterEnabled(view) {
  return !!view?.state.field(typewriterState)
}

export function getTypewriterSyncData(view) {
  if (!view?.state.field(typewriterState)) return null

  const cursorPos = view.state.selection.main.head
  const doc = view.state.doc
  return {
    currentLine: doc.lineAt(cursorPos).number,
    totalLines: doc.lines
  }
}

export function setTypewriterSelecting(view, selecting) {
  if (!view) return
  view.dispatch({
    effects: setTypewriterSelectingEffect.of(!!selecting)
  })
}
