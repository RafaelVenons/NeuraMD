import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropZone", "dropLabel", "fileInput", "baseTag", "importTag"]

  clickZone() {
    this.fileInputTarget.click()
  }

  fileSelected() {
    const file = this.fileInputTarget.files[0]
    if (file) {
      this.dropLabelTarget.textContent = file.name
      this.dropZoneTarget.classList.add("fi-new__dropzone--has-file")
    }
  }

  dragover(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.add("fi-new__dropzone--dragover")
  }

  dragleave() {
    this.dropZoneTarget.classList.remove("fi-new__dropzone--dragover")
  }

  drop(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove("fi-new__dropzone--dragover")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.fileInputTarget.files = files
      this.fileSelected()
    }
  }

  syncImportTag() {
    const base = this.baseTagTarget.value.trim()
    if (base && this.hasImportTagTarget) {
      const importTag = this.importTagTarget
      if (!importTag.dataset.userEdited) {
        importTag.value = `${base}-import`
      }
    }
  }
}
