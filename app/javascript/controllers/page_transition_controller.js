import { Controller } from "@hotwired/stimulus"
import { persistNoteGraphRect, submitFormWithPageTransition, visitWithPageTransition } from "lib/page_transition"

export default class extends Controller {
  connect() {
    this._persistNoteGraphRect = () => this.persistNoteGraphRect()
    window.addEventListener("resize", this._persistNoteGraphRect)
    requestAnimationFrame(() => this.persistNoteGraphRect())
  }

  disconnect() {
    window.removeEventListener("resize", this._persistNoteGraphRect)
  }

  submit(event) {
    const form = event.currentTarget
    if (!(form instanceof HTMLFormElement)) return

    event.preventDefault()
    submitFormWithPageTransition(form, { kind: form.dataset.transitionKind })
  }

  navigate(event) {
    const link = event.currentTarget
    const href = link?.getAttribute("href")
    if (!href) return

    event.preventDefault()
    visitWithPageTransition(href, { kind: link.dataset.transitionKind })
  }

  persistNoteGraphRect() {
    const noteGraph = document.querySelector(".note-graph-embed")
    if (!noteGraph) return

    persistNoteGraphRect(noteGraph)
  }
}
