import { Controller } from "@hotwired/stimulus"
import { parseMarkdownTable, generateMarkdownTable } from "lib/table_utils"

export default class extends Controller {
  static targets = ["dialog", "grid"]

  connect() {
    this.tableData = []
    this.editMode = false
    this.startPos = 0
    this.endPos = 0
    this._undoStack = []
  }

  open() {
    this._initNewTable()
    this._undoStack = []
    this.renderGrid()
    this.dialogTarget.showModal()
    this.dialogTarget.focus({ preventScroll: true })
  }

  openFromSelection(existingTable, startPos, endPos) {
    this.editMode = true
    this.startPos = startPos
    this.endPos = endPos
    this.tableData = parseMarkdownTable(existingTable)

    if (this.tableData.length === 0) {
      this._initNewTable()
    }

    this._undoStack = []
    this.renderGrid()
    this.dialogTarget.showModal()
    this.dialogTarget.focus({ preventScroll: true })
  }

  close() {
    this.dialogTarget.close()
  }

  _initNewTable() {
    this.editMode = false
    this.tableData = [
      ["Coluna 1", "Coluna 2", "Coluna 3"],
      ["", "", ""],
      ["", "", ""]
    ]
  }

  _pushUndo() {
    this._undoStack.push(JSON.parse(JSON.stringify(this.tableData)))
    if (this._undoStack.length > 50) this._undoStack.shift()
  }

  undo() {
    if (this._undoStack.length === 0) return
    this.tableData = this._undoStack.pop()
    this.renderGrid()
  }

  getMarkdownOutput() {
    return generateMarkdownTable(this.tableData)
  }

  renderGrid() {
    const rows = this.tableData.length
    const cols = this.tableData[0]?.length || 3
    const trashSvg = '<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>'

    let html = '<table class="table-editor-grid w-full" style="border-collapse: collapse;">'

    // Header row with delete-column icons
    html += '<tr>'
    html += '<td class="table-editor-gutter"></td>' // gutter for row-delete icons
    for (let c = 0; c < cols; c++) {
      const value = this.tableData[0]?.[c] || ""
      html += `
        <td class="font-semibold table-editor-cell" style="position: relative;">
          <input type="text" value="${this._escapeHtml(value)}"
            data-row="0" data-col="${c}"
            data-action="input->table-editor#onCellInput"
            class="table-editor-input font-semibold"
            placeholder="Cabecalho">
          ${cols > 1 ? `<button type="button" class="table-editor-delete-col" data-col="${c}"
            data-action="click->table-editor#deleteColumn" title="Excluir coluna">${trashSvg}</button>` : ""}
        </td>`
    }
    // Phantom column "+"
    html += `
      <td class="table-editor-phantom-col">
        <input type="text" value="" data-row="0" data-action="input->table-editor#onPhantomColInput"
          class="table-editor-input table-editor-phantom-input" placeholder="+">
      </td>`
    html += '</tr>'

    // Data rows
    for (let r = 1; r < rows; r++) {
      html += '<tr>'
      // Row delete icon (outside table visually, in gutter)
      html += `
        <td class="table-editor-gutter">
          ${rows > 2 ? `<button type="button" class="table-editor-delete-row" data-row="${r}"
            data-action="click->table-editor#deleteRow" title="Excluir linha">${trashSvg}</button>` : ""}
        </td>`
      for (let c = 0; c < cols; c++) {
        const value = this.tableData[r]?.[c] || ""
        html += `
          <td class="table-editor-cell">
            <input type="text" value="${this._escapeHtml(value)}"
              data-row="${r}" data-col="${c}"
              data-action="input->table-editor#onCellInput"
              class="table-editor-input"
              placeholder="">
          </td>`
      }
      // Phantom column cell
      html += `
        <td class="table-editor-phantom-col">
          <input type="text" value="" data-row="${r}" data-action="input->table-editor#onPhantomColInput"
            class="table-editor-input table-editor-phantom-input" placeholder="+">
        </td>`
      html += '</tr>'
    }

    // Phantom row "+"
    html += '<tr class="table-editor-phantom-row">'
    html += '<td class="table-editor-gutter"></td>'
    for (let c = 0; c < cols; c++) {
      html += `
        <td class="table-editor-cell">
          <input type="text" value="" data-col="${c}" data-action="input->table-editor#onPhantomRowInput"
            class="table-editor-input table-editor-phantom-input" placeholder="+">
        </td>`
    }
    html += '<td class="table-editor-phantom-col"></td>'
    html += '</tr>'

    html += '</table>'
    this.gridTarget.innerHTML = html

    // Bind Ctrl+Z on the grid
    this.gridTarget.onkeydown = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "z") {
        e.preventDefault()
        this.undo()
      }
    }
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  onCellInput(event) {
    const row = parseInt(event.target.dataset.row)
    const col = parseInt(event.target.dataset.col)
    this.tableData[row][col] = event.target.value
  }

  onPhantomColInput(event) {
    const value = event.target.value
    if (!value) return

    this._pushUndo()
    const row = parseInt(event.target.dataset.row)
    const cols = this.tableData[0]?.length || 0

    // Add new column to all rows
    for (let r = 0; r < this.tableData.length; r++) {
      this.tableData[r].push(r === 0 ? `Coluna ${cols + 1}` : "")
    }

    // Set the typed value
    this.tableData[row][cols] = value

    this.renderGrid()
    // Focus the new cell
    this._focusCell(row, cols)
  }

  onPhantomRowInput(event) {
    const value = event.target.value
    if (!value) return

    this._pushUndo()
    const col = parseInt(event.target.dataset.col)
    const cols = this.tableData[0]?.length || 0
    const newRow = new Array(cols).fill("")
    newRow[col] = value
    this.tableData.push(newRow)

    const newRowIndex = this.tableData.length - 1
    this.renderGrid()
    this._focusCell(newRowIndex, col)
  }

  deleteColumn(event) {
    const col = parseInt(event.currentTarget.dataset.col)
    const cols = this.tableData[0]?.length || 0
    if (cols <= 1) return

    this._pushUndo()
    for (let r = 0; r < this.tableData.length; r++) {
      this.tableData[r].splice(col, 1)
    }
    this.renderGrid()
  }

  deleteRow(event) {
    const row = parseInt(event.currentTarget.dataset.row)
    if (this.tableData.length <= 2 || row === 0) return

    this._pushUndo()
    this.tableData.splice(row, 1)
    this.renderGrid()
  }

  insert() {
    if (!this.tableData || this.tableData.length === 0) {
      this.close()
      return
    }

    const markdown = this.getMarkdownOutput()

    this.dispatch("insert", {
      detail: {
        markdown,
        editMode: this.editMode,
        startPos: this.startPos,
        endPos: this.endPos
      },
      bubbles: true
    })

    this.close()
  }

  _focusCell(row, col) {
    requestAnimationFrame(() => {
      const input = this.gridTarget.querySelector(`input[data-row="${row}"][data-col="${col}"]`)
      if (input) {
        input.focus()
        input.setSelectionRange(input.value.length, input.value.length)
      }
    })
  }
}
