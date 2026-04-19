import { Controller } from "@hotwired/stimulus"

const SAVE_DEBOUNCE_MS = 800

export default class extends Controller {
  static targets = ["list", "input", "status"]
  static values = { url: String, csrf: String }

  connect() {
    this.todos = []
    this.saveTimer = null
    this.load()
  }

  disconnect() {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
      this.flush()
    }
  }

  async load() {
    this.setStatus("carregando…")
    try {
      const res = await fetch(this.urlValue, {
        credentials: "same-origin",
        headers: { "Accept": "application/json" }
      })
      if (!res.ok) throw new Error(`load failed (${res.status})`)
      const body = await res.json()
      this.todos = Array.isArray(body.todos) ? body.todos : []
      this.render()
      this.setStatus(this.todos.length ? `${this.todos.length}` : "vazio")
    } catch (err) {
      console.error(err)
      this.setStatus("erro")
    }
  }

  add(event) {
    event.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text) return
    this.todos.push({ text, done: false })
    this.inputTarget.value = ""
    this.render()
    this.scheduleSave()
  }

  toggle(event) {
    const index = Number(event.target.dataset.index)
    if (Number.isNaN(index) || !this.todos[index]) return
    this.todos[index].done = event.target.checked
    this.render()
    this.scheduleSave()
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (Number.isNaN(index)) return
    this.todos.splice(index, 1)
    this.render()
    this.scheduleSave()
  }

  render() {
    const listEl = this.listTarget
    listEl.replaceChildren()
    this.todos.forEach((todo, index) => {
      const li = document.createElement("li")
      li.className = "nm-tentacle__todo" + (todo.done ? " nm-tentacle__todo--done" : "")

      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.checked = !!todo.done
      checkbox.dataset.index = String(index)
      checkbox.addEventListener("change", (e) => this.toggle(e))

      const text = document.createElement("span")
      text.className = "nm-tentacle__todo-text"
      text.textContent = todo.text

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "nm-tentacle__todo-remove"
      remove.dataset.index = String(index)
      remove.setAttribute("aria-label", "Remover")
      remove.textContent = "×"
      remove.addEventListener("click", (e) => this.remove(e))

      li.append(checkbox, text, remove)
      listEl.append(li)
    })
  }

  scheduleSave() {
    this.setStatus("salvando…")
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.flush(), SAVE_DEBOUNCE_MS)
  }

  async flush() {
    this.saveTimer = null
    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ todos: this.todos })
      })
      if (!res.ok) throw new Error(`save failed (${res.status})`)
      const body = await res.json()
      this.todos = Array.isArray(body.todos) ? body.todos : this.todos
      this.render()
      this.setStatus(this.todos.length ? `${this.todos.length}` : "vazio")
    } catch (err) {
      console.error(err)
      this.setStatus("erro")
    }
  }

  setStatus(label) {
    if (this.hasStatusTarget) this.statusTarget.textContent = label
  }
}
