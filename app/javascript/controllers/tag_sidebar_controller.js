import { Controller } from "@hotwired/stimulus"
import { trigramScore } from "lib/trigram_search"
import { ColorPicker } from "lib/tag_sidebar/color_picker"

// Left sidebar for managing tags.
//
// Two modes driven by wikilink:cursor events from wikilink_controller:
//
//   LINK MODE (cursor inside [[Display|uuid]]):
//     Tags shown as checkboxes (SVG with checkmark when active).
//     Multiple tags can be active simultaneously for the same link (N:N).
//     Checked tags float to the top with smooth FLIP animation.
//
//   GLOBAL MODE (cursor outside any wiki-link):
//     Tags shown as plain dots. One tag active at a time.
//     Clicking a tag highlights all links with that tag in the preview.
//
// New tag flow:
//   1. User clicks "+" dot → custom color picker popup opens (position: fixed).
//   2. User picks a suggested color (harmony-based from existing palette) or
//      uses the hue slider for a custom color.
//   3. If name is already typed → tag is created immediately on color pick.
//      If name is empty → picker closes, focus goes to name input.
//   4. Enter in name input or ✓ button → creates tag.
//   5. Click outside picker without picking → dismisses with no effect.
export default class extends Controller {
  static values  = { noteSlug: String, linkTagsData: String }
  static targets = [
    "list", "nameInput", "modeLabel", "searchInput", "newDotBtn", "newRow",
    "colorPicker", "colorSuggestions", "colorWheel", "colorPreview", "colorHex", "colorWcag"
  ]

  connect() {
    this._collapsed        = false
    this._creatingTag      = false
    this._tags             = []
    this._focusedLink      = null
    this._activatedTagId   = null
    this._newColor         = "#3b82f6"
    this._linkTagsMap      = this._parseLinkTagsData()
    this._searchOpen       = false
    this._searchQuery      = ""

    this._colorPicker = new ColorPicker(
      {
        picker: this.hasColorPickerTarget ? this.colorPickerTarget : null,
        suggestions: this.hasColorSuggestionsTarget ? this.colorSuggestionsTarget : null,
        wheel: this.hasColorWheelTarget ? this.colorWheelTarget : null,
        preview: this.hasColorPreviewTarget ? this.colorPreviewTarget : null,
        hex: this.hasColorHexTarget ? this.colorHexTarget : null,
        wcag: this.hasColorWcagTarget ? this.colorWcagTarget : null
      },
      {
        onColorSelected: (hex) => this._selectColor(hex),
        onWheelColorChanged: (hex) => { this._newColor = hex; this._updateNewDot() },
        getTagData: () => ({ tags: this._tags, tagUsage: this._tagUsageInNote() })
      }
    )

    this._onWikilinkCursor = this._handleWikilinkCursor.bind(this)
    document.addEventListener("wikilink:cursor", this._onWikilinkCursor)

    this._onDocClick = (e) => {
      if (!this._colorPicker.isOpen()) return
      if (this.hasColorPickerTarget && this.colorPickerTarget.contains(e.target)) return
      if (this.hasNewDotBtnTarget && this.newDotBtnTarget.contains(e.target)) return
      this._colorPicker.close()
    }
    document.addEventListener("click", this._onDocClick)

    this._updateNewDot()
    this._loadTags()
  }

  disconnect() {
    document.removeEventListener("wikilink:cursor", this._onWikilinkCursor)
    document.removeEventListener("click", this._onDocClick)
    this._clearHighlight()
  }

  hydrateNoteContext(payload) {
    const note = payload.note || {}

    this.noteSlugValue = note.slug || this.noteSlugValue
    this.linkTagsDataValue = JSON.stringify(payload.link_tags_map || {})
    this._linkTagsMap = this._parseLinkTagsData()
    this._focusedLink = null
    this._activatedTagId = null
    this._searchQuery = ""
    if (this.hasSearchInputTarget) this.searchInputTarget.value = ""
    this._clearHighlight()
    this._renderList()
  }

  // ── Collapse toggle ──────────────────────────────────────

  toggle() {
    this._collapsed = !this._collapsed
    this.element.classList.toggle("tag-sidebar--collapsed", this._collapsed)
    if (this._collapsed) this._closeSearchField()
  }

  openSearch() {
    if (this._collapsed || !this.hasSearchInputTarget || !this.hasModeLabelTarget) return
    this._searchOpen = true
    this.modeLabelTarget.hidden = true
    this.searchInputTarget.hidden = false
    this.searchInputTarget.value = this._searchQuery
    this.searchInputTarget.focus()
    this.searchInputTarget.select()
  }

  closeSearch() {
    if (this._searchQuery.trim()) return
    this._closeSearchField()
  }

  handleSearchKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this._searchQuery = ""
      this.searchInputTarget.value = ""
      this._closeSearchField()
      this._renderList()
    }
  }

  searchTags(event) {
    this._searchQuery = event.target.value
    this._renderList()
  }

  // ── Color picker ─────────────────────────────────────────

  openColorPicker() {
    this._colorPicker.open(this.newDotBtnTarget.getBoundingClientRect())
  }

  pickSuggestion(e) {
    this._colorPicker.selectColor(e.currentTarget.dataset.color)
  }

  confirmCustomColor() {
    this._colorPicker.confirmCustomColor()
  }

  onWheelClick(e) {
    this._colorPicker.onWheelClick(e)
  }

  onWheelHover(e) {
    this._colorPicker.onWheelHover(e)
  }

  // ── New tag interactions ─────────────────────────────────

  onNameKeydown(e) {
    if (e.key === "Enter") { e.preventDefault(); this.createTag() }
  }

  async createTag() {
    const name = this.nameInputTarget.value.trim()
    if (!name) { this.nameInputTarget.focus(); return }

    const existingTag = this._findTagByName(name)
    if (existingTag) {
      await this._useExistingTag(existingTag)
      return
    }
    if (this._creatingTag) return

    this._creatingTag = true

    try {
      const res  = await fetch("/tags", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken(), Accept: "application/json" },
        body: JSON.stringify({ tag: { name, color_hex: this._newColor, tag_scope: "both" } })
      })

      if (!res.ok) {
        if (res.status === 422) {
          await this._loadTags()
          const conflictingTag = this._findTagByName(name)
          if (conflictingTag) await this._useExistingTag(conflictingTag)
        }
        return
      }

      const tag = await res.json()

      this._tags.push(tag)

      if (this._focusedLink) {
        await this._attachTagToFocusedLink(tag.id, tag)
      }

      this.nameInputTarget.value = ""
      this._setSuggestedNewColor()
      this._renderList()
    } finally {
      this._creatingTag = false
    }
  }

  async deleteTag(tagId) {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    await fetch(`/tags/${tagId}`, { method: "DELETE", headers: { "X-CSRF-Token": csrf } })
    this._tags = this._tags.filter(t => t.id !== tagId)
    this._setSuggestedNewColor()
    this._renderList()
  }

  // ── Wikilink cursor event ────────────────────────────────

  async _handleWikilinkCursor(e) {
    const link = e.detail.link
    this._clearHighlight()
    this._activatedTagId = null

    if (link) {
      this._focusedLink = { uuid: link.uuid, link_id: null, tags: [] }
      this._renderList()

      try {
        const res = await fetch(
          `/notes/${this.noteSlugValue}/link_info?dst_uuid=${link.uuid}`,
          { headers: { Accept: "application/json" } }
        )
        if (res.ok) {
          const data = await res.json()
          if (this._focusedLink?.uuid === link.uuid && data.link_id) {
            this._focusedLink = { uuid: link.uuid, link_id: data.link_id, tags: data.tags }
            this._renderList()
          }
        }
      } catch (_) {}
    } else {
      this._focusedLink = null
      this._renderList()
    }
  }

  // ── Tag loading ──────────────────────────────────────────

  async _loadTags() {
    try {
      const res = await fetch("/tags", { headers: { Accept: "application/json" } })
      if (!res.ok) return
      this._tags = await res.json()
      this._setSuggestedNewColor()
      this._renderList()
    } catch (_) {}
  }

  // ── Rendering with FLIP animation ───────────────────────

  _renderList() {
    const newRow = this.hasNewRowTarget ? this.newRowTarget : null
    const before = new Map()
    this.listTarget.querySelectorAll("li[data-tag-id]").forEach(el => {
      before.set(el.dataset.tagId, el.getBoundingClientRect().top)
    })

    if (this.hasModeLabelTarget) {
      this.modeLabelTarget.textContent = this._focusedLink ? "Link" : "Global"
    }

    if (this._focusedLink) {
      this._renderLinkMode()
    } else {
      this._renderGlobalMode()
    }

    if (newRow) this.listTarget.appendChild(newRow)

    requestAnimationFrame(() => {
      this.listTarget.querySelectorAll("li[data-tag-id]").forEach(el => {
        const id = el.dataset.tagId
        if (!before.has(id)) return
        const delta = before.get(id) - el.getBoundingClientRect().top
        if (Math.abs(delta) < 1) return
        el.style.transition = "none"
        el.style.transform  = `translateY(${delta}px)`
        requestAnimationFrame(() => {
          el.style.transition = "transform 0.25s cubic-bezier(0.25, 0.46, 0.45, 0.94)"
          el.style.transform  = "translateY(0)"
        })
      })
    })
  }

  _renderLinkMode() {
    const linkedTagIds = new Set((this._focusedLink?.tags || []).map(t => t.id))
    const usage        = this._tagUsageInNote()

    const sorted = this._filterAndSortTags((a, b) => {
      const aOn = linkedTagIds.has(a.id) ? 1 : 0
      const bOn = linkedTagIds.has(b.id) ? 1 : 0
      if (aOn !== bOn) return bOn - aOn
      return (usage[b.id] || 0) - (usage[a.id] || 0)
    })

    this.listTarget.innerHTML = sorted.map(tag => {
      const checked = linkedTagIds.has(tag.id)
      const dot     = checked ? this._checkDotSvg(tag.color_hex) : this._dotSvg(tag.color_hex)
      return `
        <li class="tag-item ${checked ? "tag-item--active" : ""}"
            data-tag-id="${tag.id}"
            data-action="click->tag-sidebar#toggleLinkTag"
            title="${this._esc(tag.name)}">
          ${dot}
          <span class="tag-name" style="color:${tag.color_hex}">${this._esc(tag.name)}</span>
        </li>`
    }).join("")
  }

  _renderGlobalMode() {
    const usage = this._tagUsageInNote()
    const sorted = this._filterAndSortTags((a, b) => {
      const aA = this._activatedTagId === a.id ? 1 : 0
      const bA = this._activatedTagId === b.id ? 1 : 0
      if (aA !== bA) return bA - aA

      const usageDelta = (usage[b.id] || 0) - (usage[a.id] || 0)
      if (usageDelta !== 0) return usageDelta

      return a.name.localeCompare(b.name, "pt-BR")
    })

    this.listTarget.innerHTML = sorted.map(tag => {
      const active = this._activatedTagId === tag.id
      return `
        <li class="tag-item ${active ? "tag-item--highlight" : ""}"
            data-tag-id="${tag.id}"
            data-tag-color="${tag.color_hex}"
            data-action="click->tag-sidebar#toggleGlobalHighlight"
            title="${this._esc(tag.name)}">
          ${this._dotSvg(tag.color_hex)}
          <span class="tag-name" style="color:${tag.color_hex}">${this._esc(tag.name)}</span>
          <button class="tag-delete-btn"
                  data-tag-id="${tag.id}"
                  data-action="click->tag-sidebar#handleDelete"
                  title="Apagar tag">
            <svg viewBox="0 0 16 16" width="10" height="10" fill="none"
                 stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
              <line x1="3" y1="3" x2="13" y2="13"/><line x1="13" y1="3" x2="3" y2="13"/>
            </svg>
          </button>
        </li>`
    }).join("")
  }

  _filterAndSortTags(baseSorter) {
    const tags = [...this._tags]
    const query = this._searchQuery.trim()
    if (!query) return tags.sort(baseSorter)

    return tags
      .map((tag) => ({ tag, score: this._tagSearchScore(tag.name, query) }))
      .filter(({ score }) => score > 0)
      .sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score
        return baseSorter(a.tag, b.tag)
      })
      .map(({ tag }) => tag)
  }

  _tagSearchScore(name, query) {
    return trigramScore(name, query)
  }

  _closeSearchField() {
    this._searchOpen = false
    if (this.hasSearchInputTarget) this.searchInputTarget.hidden = true
    if (this.hasModeLabelTarget) this.modeLabelTarget.hidden = false
  }

  // ── Link-mode: N:N tag toggle ────────────────────────────

  async toggleLinkTag(e) {
    const li    = e.currentTarget.closest("[data-tag-id]")
    const tagId = li?.dataset.tagId
    if (!tagId) return

    const linkedTagIds = new Set((this._focusedLink.tags || []).map(t => t.id))

    if (linkedTagIds.has(tagId)) {
      await fetch("/link_tags", {
        method: "DELETE",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
        body: JSON.stringify({ note_link_id: this._focusedLink.link_id, tag_id: tagId })
      })
      this._focusedLink.tags = this._focusedLink.tags.filter(t => t.id !== tagId)
      if (this._linkTagsMap[this._focusedLink.uuid]) {
        this._linkTagsMap[this._focusedLink.uuid] =
          this._linkTagsMap[this._focusedLink.uuid].filter(id => id !== tagId)
      }
    } else {
      const tag = this._tags.find(t => t.id === tagId)
      await this._attachTagToFocusedLink(tagId, tag)
    }

    this._renderList()
  }

  async _attachTagToFocusedLink(tagId, tag = null) {
    if (!this._focusedLink?.link_id) {
      const hydratedLink = await this._ensureFocusedLinkSaved()
      if (!hydratedLink?.link_id) return false
    }

    const res = await fetch("/link_tags", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this._csrfToken() },
      body: JSON.stringify({ note_link_id: this._focusedLink.link_id, tag_id: tagId })
    })
    if (!res.ok) return false

    const normalizedTagId = String(tagId)
    if (tag && !this._focusedLink.tags.some(t => t.id === normalizedTagId)) {
      this._focusedLink.tags.push(tag)
    }
    if (!this._linkTagsMap[this._focusedLink.uuid]) this._linkTagsMap[this._focusedLink.uuid] = []
    if (!this._linkTagsMap[this._focusedLink.uuid].includes(normalizedTagId)) {
      this._linkTagsMap[this._focusedLink.uuid].push(normalizedTagId)
    }
    return true
  }

  async _ensureFocusedLinkSaved() {
    const uuid = this._focusedLink?.uuid
    if (!uuid) return null

    await this._getAutosaveController()?.saveDraftNow()

    try {
      const res = await fetch(
        `/notes/${this.noteSlugValue}/link_info?dst_uuid=${uuid}`,
        { headers: { Accept: "application/json" } }
      )
      if (!res.ok) return null

      const data = await res.json()
      if (!data.link_id) return null

      if (this._focusedLink?.uuid === uuid) {
        this._focusedLink = { uuid, link_id: data.link_id, tags: data.tags }
        this._renderList()
      }

      return this._focusedLink
    } catch (_) {
      return null
    }
  }

  _getAutosaveController() {
    const root = this.element.closest("[data-controller~='autosave']")
    if (!root) return null

    return this.application.getControllerForElementAndIdentifier(root, "autosave")
  }

  _csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  _findTagByName(name) {
    const normalizedName = name.trim().toLowerCase()
    return this._tags.find(tag => tag.name.trim().toLowerCase() === normalizedName) || null
  }

  async _useExistingTag(tag) {
    if (this._focusedLink) {
      await this._attachTagToFocusedLink(tag.id, tag)
    }

    this.nameInputTarget.value = ""
    this._setSuggestedNewColor()
    this._renderList()
  }

  // ── Global-mode: single-tag highlight ───────────────────

  toggleGlobalHighlight(e) {
    const li    = e.currentTarget
    const tagId = li.dataset.tagId
    const color = li.dataset.tagColor

    if (this._activatedTagId === tagId) {
      this._activatedTagId = null
      this._clearHighlight()
    } else {
      this._activatedTagId = tagId
      this._applyHighlight(tagId, color)
    }
    this._renderList()
  }

  handleDelete(e) {
    e.stopPropagation()
    const tagId = e.currentTarget.dataset.tagId
    if (tagId) this.deleteTag(tagId)
  }

  // ── Highlight helpers ────────────────────────────────────

  _applyHighlight(tagId, color) {
    const uuids = Object.entries(this._linkTagsMap)
      .filter(([, tagIds]) => tagIds.includes(tagId))
      .map(([uuid]) => uuid)

    document.querySelectorAll(".preview-prose a[data-uuid]").forEach(a => {
      const highlight = uuids.includes(a.dataset.uuid)
      a.classList.toggle("wikilink-tag-highlight", highlight)
      if (highlight) a.style.setProperty("--tag-highlight-color", color)
    })
  }

  _clearHighlight() {
    document.querySelectorAll(".wikilink-tag-highlight").forEach(a => {
      a.classList.remove("wikilink-tag-highlight")
      a.style.removeProperty("--tag-highlight-color")
    })
  }

  // ── Color selection ──────────────────────────────────────

  _selectColor(hex) {
    this._newColor = hex
    this._updateNewDot()

    if (this._collapsed) {
      this._collapsed = false
      this.element.classList.remove("tag-sidebar--collapsed")
    }

    if (this.nameInputTarget.value.trim()) {
      this.createTag()
    } else {
      this.nameInputTarget.focus()
    }
  }

  // Flash the notice row to draw attention when user tries to tag without a checkpoint.
  _flashNotice() {
    const notice = this.listTarget.querySelector(".tag-link-notice")
    if (!notice) return
    notice.classList.add("tag-link-notice--flash")
    setTimeout(() => notice.classList.remove("tag-link-notice--flash"), 700)
  }

  // ── SVG dot helpers ──────────────────────────────────────

  _dotSvg(color) {
    return `<svg class="tag-dot-svg" viewBox="0 0 20 20" width="22" height="22">
      <circle cx="10" cy="10" r="9" fill="${this._esc(color)}"
              stroke="rgba(255,255,255,0.2)" stroke-width="1.5"/>
    </svg>`
  }

  _checkDotSvg(color) {
    return `<svg class="tag-dot-svg" viewBox="0 0 20 20" width="22" height="22">
      <circle cx="10" cy="10" r="9" fill="${this._esc(color)}"
              stroke="rgba(255,255,255,0.3)" stroke-width="1.5"/>
      <polyline points="6.5,10.5 9,13 13.5,7" fill="none"
                stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`
  }

  _updateNewDot() {
    if (!this.hasNewDotBtnTarget) return
    const c = this._esc(this._newColor || "#3b82f6")
    this.newDotBtnTarget.innerHTML = `
      <svg viewBox="0 0 20 20" width="22" height="22">
        <circle cx="10" cy="10" r="9" fill="${c}"
                stroke="rgba(255,255,255,0.25)" stroke-width="1.5"/>
        <line x1="10" y1="6" x2="10" y2="14" stroke="white" stroke-width="2" stroke-linecap="round"/>
        <line x1="6" y1="10" x2="14" y2="10" stroke="white" stroke-width="2" stroke-linecap="round"/>
      </svg>`
  }

  // ── Utils ────────────────────────────────────────────────

  _tagUsageInNote() {
    const counts = {}
    Object.values(this._linkTagsMap).flat().forEach(id => {
      counts[id] = (counts[id] || 0) + 1
    })
    return counts
  }

  _setSuggestedNewColor() {
    const suggested = this._colorPicker.suggestNextColor()
    if (!suggested) return

    this._newColor = suggested
    this._colorPicker.setHueFromHex(suggested)
    this._updateNewDot()
  }

  _parseLinkTagsData() {
    try { return JSON.parse(this.linkTagsDataValue || "{}") } catch (_) { return {} }
  }

  _esc(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
