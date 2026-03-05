export function wrapSelection(editor, before, after) {
  const selection = editor.getSelection()
  if (selection) {
    editor.replaceSelection(`${before}${selection}${after}`)
  } else {
    const placeholder = before.trim() || "texto"
    editor.replaceSelection(`${before}${placeholder}${after}`)
  }
}

export function insertAtCursor(editor, text) {
  editor.replaceSelection(text)
}
