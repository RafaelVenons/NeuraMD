import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tbody", "splitsInput", "count"]

  changed(event) {
    const input = event.target
    const index = parseInt(input.dataset.index, 10)
    const field = input.dataset.field

    const splits = JSON.parse(this.splitsInputTarget.value)
    if (!splits[index]) return

    if (field === "title") {
      splits[index].title = input.value
    } else if (field === "start_line" || field === "end_line") {
      splits[index][field] = parseInt(input.value, 10) || 0
      splits[index].line_count = splits[index].end_line - splits[index].start_line + 1

      // Update count display
      const countEl = this.countTargets.find(el => el.dataset.index === String(index))
      if (countEl) countEl.textContent = splits[index].line_count
    }

    this.splitsInputTarget.value = JSON.stringify(splits)
  }
}
