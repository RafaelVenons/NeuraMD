import { RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView } from "@codemirror/view"
import { computeWordDiff } from "lib/diff_utils"

const setAiDiff = StateEffect.define()
const clearAiDiff = StateEffect.define()
const deletedMark = Decoration.mark({ class: "cm-ai-diff-deleted" })

const aiDiffState = StateField.define({
  create() {
    return {
      decorations: Decoration.none,
      originalText: "",
      aiSuggestedText: ""
    }
  },
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(clearAiDiff)) {
        return {
          decorations: Decoration.none,
          originalText: "",
          aiSuggestedText: ""
        }
      }

      if (effect.is(setAiDiff)) {
        const originalText = effect.value.originalText || ""
        const aiSuggestedText = effect.value.aiSuggestedText || ""

        return {
          originalText,
          aiSuggestedText,
          decorations: buildDecorations(originalText, aiSuggestedText)
        }
      }
    }

    if (!transaction.docChanged) {
      return value
    }

    return {
      decorations: Decoration.none,
      originalText: "",
      aiSuggestedText: ""
    }
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations)
})

export function aiDiffExtension() {
  return aiDiffState
}

export function setAiDiffEffect(payload) {
  return setAiDiff.of(payload)
}

export function clearAiDiffEffect() {
  return clearAiDiff.of(null)
}

function buildDecorations(originalText, aiSuggestedText) {
  const builder = new RangeSetBuilder()
  let position = 0

  computeWordDiff(originalText, aiSuggestedText).forEach((part) => {
    if (part.type === "equal") {
      position += part.value.length
      return
    }

    if (part.type === "delete") {
      builder.add(position, position + part.value.length, deletedMark)
      position += part.value.length
    }
  })

  return builder.finish()
}
