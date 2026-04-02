export class KeyboardShortcuts {
  constructor(bindings, getComposingState) {
    this._bindings = bindings
    this._getComposingState = getComposingState
    this._handler = (e) => this._handleKeydown(e)
  }

  install() {
    document.addEventListener("keydown", this._handler)
  }

  destroy() {
    document.removeEventListener("keydown", this._handler)
  }

  _handleKeydown(e) {
    if (e.isComposing || e.keyCode === 229 || this._getComposingState()) return
    const ctrl = e.ctrlKey || e.metaKey

    for (const binding of this._bindings) {
      if (binding.ctrl && !ctrl) continue
      if (binding.shift && !e.shiftKey) continue
      if (e.key !== binding.key) continue
      if (binding.preventDefault !== false) e.preventDefault()
      binding.action()
      return
    }
  }
}
