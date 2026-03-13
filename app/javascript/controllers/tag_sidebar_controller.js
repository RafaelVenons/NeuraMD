import { Controller } from "@hotwired/stimulus"

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
    "list", "nameInput", "modeLabel", "newDotBtn", "newRow",
    "colorPicker", "colorSuggestions", "colorWheel", "colorPreview", "colorHex", "colorWcag"
  ]

  connect() {
    this._collapsed        = false
    this._creatingTag      = false
    this._tags             = []
    this._focusedLink      = null
    this._activatedTagId   = null
    this._newColor         = "#3b82f6"
    this._currentWheelHue  = 216   // default blue hue for the color wheel
    this._linkTagsMap      = this._parseLinkTagsData()

    this._onWikilinkCursor = this._handleWikilinkCursor.bind(this)
    document.addEventListener("wikilink:cursor", this._onWikilinkCursor)

    // Close picker on outside click
    this._onDocClick = (e) => {
      if (!this.hasColorPickerTarget) return
      if (this.colorPickerTarget.hidden) return
      if (this.colorPickerTarget.contains(e.target)) return
      if (this.newDotBtnTarget.contains(e.target)) return
      this.colorPickerTarget.hidden = true
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

  // ── Collapse toggle ──────────────────────────────────────

  toggle() {
    this._collapsed = !this._collapsed
    this.element.classList.toggle("tag-sidebar--collapsed", this._collapsed)
  }

  // ── Color picker ─────────────────────────────────────────

  openColorPicker() {
    const popup = this.colorPickerTarget
    const btn   = this.newDotBtnTarget
    const rect  = btn.getBoundingClientRect()

    // Position to the right of the dot button; flip up if too close to bottom
    const spaceBelow = window.innerHeight - rect.top
    popup.style.left = (rect.right + 8) + "px"
    if (spaceBelow < 280) {
      popup.style.bottom = (window.innerHeight - rect.bottom) + "px"
      popup.style.top    = "auto"
    } else {
      popup.style.top    = rect.top + "px"
      popup.style.bottom = "auto"
    }

    popup.hidden = false
    this._renderColorSuggestions()
    this._drawColorWheel()
    this._updateCustomPreview()
  }

  // Called when user clicks a suggested swatch
  pickSuggestion(e) {
    this._selectColor(e.currentTarget.dataset.color)
  }

  // Called when user clicks ✓ below the color wheel
  confirmCustomColor() {
    const hex = this._hslToHex(this._currentWheelHue, 75, 60)
    this._selectColor(hex)
  }

  // Click on the color wheel canvas — select hue at that position
  onWheelClick(e) {
    const hue = this._hueFromWheelEvent(e)
    if (hue === null) return
    this._currentWheelHue = hue
    this._newColor = this._hslToHex(hue, 75, 60)
    this._updateNewDot()
    this._updateCustomPreview()
    this._drawColorWheel()
  }

  // Hover on canvas — preview hue without committing
  onWheelHover(e) {
    const hue = this._hueFromWheelEvent(e)
    if (hue === null) return
    this._drawColorWheel(hue)
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

    const sorted = [...this._tags].sort((a, b) => {
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
    const sorted = [...this._tags].sort((a, b) => {
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

  // ── Color picker — suggestion engine (Chroma-based) ─────

  // Select a color: update state, close picker, create tag or focus input.
  _selectColor(hex) {
    this._newColor = hex
    this._updateNewDot()
    if (this.hasColorPickerTarget) this.colorPickerTarget.hidden = true

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

  // Render suggestion swatches based on harmony analysis of existing tag colors.
  _renderColorSuggestions() {
    const suggestions = this._generateSuggestions()
    this.colorSuggestionsTarget.innerHTML = suggestions.map(hex => {
      const wcag  = this._contrastOnDark(hex)
      const badge = wcag !== "FAIL"
        ? `<span class="tcp-wcag-dot tcp-wcag-dot--${wcag.startsWith("AAA") ? "aaa" : "aa"}"></span>`
        : ""
      return `
        <button type="button"
                class="tcp-swatch"
                style="background:${this._esc(hex)}"
                title="${this._esc(hex)} · ${wcag}"
                data-action="click->tag-sidebar#pickSuggestion"
                data-color="${this._esc(hex)}">
          ${badge}
        </button>`
    }).join("")
  }

  // Update the custom-color preview row below the wheel.
  _updateCustomPreview() {
    if (!this.hasColorPreviewTarget) return
    const hex  = this._hslToHex(this._currentWheelHue, 75, 60)
    const wcag = this._contrastOnDark(hex)

    this.colorPreviewTarget.style.background = hex
    this.colorHexTarget.textContent          = hex
    this.colorWcagTarget.textContent         = wcag
    this.colorWcagTarget.className =
      `tcp-wcag tcp-wcag--${wcag === "FAIL" ? "fail" : wcag.startsWith("AAA") ? "aaa" : "aa"}`
  }

  // Generate up to 12 color suggestions using harmony from existing tag palette.
  // Falls back to a preset palette when no tags exist.
  _generateSuggestions() {
    const presets = [
      "#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899",
      "#06b6d4", "#84cc16", "#f97316", "#6366f1", "#14b8a6", "#f43f5e"
    ]

    const seen = new Set()
    const suggestions = []
    const usageColors = this._dominantTagColors()

    usageColors.forEach(({ hue }, index) => {
      const offsets = index === 0 ? [180, 150, 210, 120, 240, 90] : [180, 120, 240]
      offsets.forEach(offset => {
        const newHex = this._hslToHex((hue + offset) % 360, 75, 60)
        const key = newHex.toLowerCase()
        if (!seen.has(key) && !this._hasSimilarTagColor(newHex)) {
          seen.add(key)
          suggestions.push(newHex)
        }
      })
    })

    const nextColor = this._suggestNextColor()
    if (nextColor && !seen.has(nextColor.toLowerCase())) {
      seen.add(nextColor.toLowerCase())
      suggestions.unshift(nextColor)
    }

    presets.forEach(c => {
      const key = c.toLowerCase()
      if (!seen.has(key) && !this._hasSimilarTagColor(c) && suggestions.length < 12) {
        seen.add(key)
        suggestions.push(c)
      }
    })

    return suggestions.slice(0, 12)
  }

  // ── Color math (ported from color/color-tool.html) ───────

  _hslToHex(h, s, l) {
    s /= 100; l /= 100
    const a = s * Math.min(l, 1 - l)
    const f = n => {
      const k = (n + h / 30) % 12
      return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
    }
    return "#" + [f(0), f(8), f(4)]
      .map(x => Math.round(x * 255).toString(16).padStart(2, "0"))
      .join("")
  }

  _hexToHsl(hex) {
    let r = parseInt(hex.slice(1, 3), 16) / 255
    let g = parseInt(hex.slice(3, 5), 16) / 255
    let b = parseInt(hex.slice(5, 7), 16) / 255
    const max = Math.max(r, g, b), min = Math.min(r, g, b)
    let h = 0, s = 0
    const l = (max + min) / 2
    if (max !== min) {
      const d = max - min
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
      switch (max) {
        case r: h = (g - b) / d + (g < b ? 6 : 0); break
        case g: h = (b - r) / d + 2; break
        case b: h = (r - g) / d + 4; break
      }
      h /= 6
    }
    return [Math.round(h * 360), Math.round(s * 100), Math.round(l * 100)]
  }

  // WCAG contrast ratio against the app's dark background (#18181b).
  _contrastOnDark(hex) {
    const lum = (h) => {
      const rgb = [1, 3, 5].map(i => {
        const c = parseInt(h.slice(i, i + 2), 16) / 255
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
      })
      return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
    }
    const l1 = lum(hex.length === 7 ? hex : "#3b82f6")
    const l2 = lum("#18181b")
    const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
    return ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "AA lg" : "FAIL"
  }

  // ── Color wheel (mini chromatic ring) ───────────────────

  // Draw the hue ring on the canvas. Pass hoverHue to show a ghost dot while hovering.
  _drawColorWheel(hoverHue = null) {
    if (!this.hasColorWheelTarget) return
    const canvas = this.colorWheelTarget
    const ctx    = canvas.getContext("2d")
    const SIZE   = 156, CX = 78, CY = 78, R = 72, IR = 38

    ctx.clearRect(0, 0, SIZE, SIZE)

    // Hue ring
    for (let angle = 0; angle < 360; angle += 0.5) {
      const r1 = (angle - 90) * Math.PI / 180
      const r2 = (angle + 0.6 - 90) * Math.PI / 180
      ctx.beginPath()
      ctx.moveTo(CX + IR * Math.cos(r1), CY + IR * Math.sin(r1))
      ctx.lineTo(CX + R  * Math.cos(r1), CY + R  * Math.sin(r1))
      ctx.lineTo(CX + R  * Math.cos(r2), CY + R  * Math.sin(r2))
      ctx.lineTo(CX + IR * Math.cos(r2), CY + IR * Math.sin(r2))
      ctx.closePath()
      ctx.fillStyle = `hsl(${angle}, 75%, 60%)`
      ctx.fill()
    }

    const midR = (R + IR) / 2

    // Ghost dot on hover (smaller, semi-transparent)
    if (hoverHue !== null && hoverHue !== this._currentWheelHue) {
      const hRad = (hoverHue - 90) * Math.PI / 180
      const hx   = CX + midR * Math.cos(hRad)
      const hy   = CY + midR * Math.sin(hRad)
      ctx.beginPath()
      ctx.arc(hx, hy, 5, 0, Math.PI * 2)
      ctx.fillStyle   = `hsla(${hoverHue}, 75%, 60%, 0.55)`
      ctx.fill()
      ctx.strokeStyle = "rgba(255,255,255,0.4)"
      ctx.lineWidth   = 1.5
      ctx.stroke()
    }

    // Current selection indicator
    const selRad = (this._currentWheelHue - 90) * Math.PI / 180
    const sx     = CX + midR * Math.cos(selRad)
    const sy     = CY + midR * Math.sin(selRad)
    ctx.beginPath()
    ctx.arc(sx, sy, 7, 0, Math.PI * 2)
    ctx.fillStyle   = this._hslToHex(this._currentWheelHue, 75, 60)
    ctx.fill()
    ctx.strokeStyle = "white"
    ctx.lineWidth   = 2
    ctx.stroke()
  }

  // Convert a canvas mouse event to a hue angle (0-359), or null if outside the ring.
  _hueFromWheelEvent(e) {
    if (!this.hasColorWheelTarget) return null
    const canvas = this.colorWheelTarget
    const rect   = canvas.getBoundingClientRect()
    const scaleX = 156 / rect.width
    const scaleY = 156 / rect.height
    const x = (e.clientX - rect.left) * scaleX - 78
    const y = (e.clientY - rect.top)  * scaleY - 78
    const dist = Math.sqrt(x * x + y * y)
    if (dist < 38 || dist > 72) return null
    let hue = Math.atan2(y, x) * 180 / Math.PI + 90
    if (hue < 0) hue += 360
    return Math.round(hue) % 360
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
    const suggested = this._suggestNextColor()
    if (!suggested) return

    this._newColor = suggested
    try {
      const [hue] = this._hexToHsl(suggested)
      this._currentWheelHue = hue
    } catch (_) {}
    this._updateNewDot()
  }

  _suggestNextColor() {
    const dominant = this._dominantTagColors()
    if (!dominant.length) return "#3b82f6"

    let best = null
    for (let hue = 0; hue < 360; hue += 15) {
      const score = dominant.reduce((acc, entry) => {
        const distance = this._angularDistance(hue, entry.hue)
        return acc + (distance * entry.weight)
      }, 0)

      if (!best || score > best.score) best = { hue, score }
    }

    return this._hslToHex(best.hue, 75, 60)
  }

  _dominantTagColors() {
    const usage = this._tagUsageInNote()

    const ranked = this._tags
      .filter(tag => tag.color_hex)
      .map(tag => ({
        hue: this._hexToHsl(tag.color_hex)[0],
        weight: usage[tag.id] || 0
      }))
      .filter(entry => entry.weight > 0)
      .sort((a, b) => b.weight - a.weight)

    if (ranked.length) return ranked.slice(0, 6)

    return this._tags
      .filter(tag => tag.color_hex)
      .slice(-6)
      .map(tag => ({ hue: this._hexToHsl(tag.color_hex)[0], weight: 1 }))
  }

  _hasSimilarTagColor(hex) {
    try {
      const [candidateHue] = this._hexToHsl(hex)
      return this._tags.some(tag => {
        if (!tag.color_hex) return false
        const [tagHue] = this._hexToHsl(tag.color_hex)
        return this._angularDistance(candidateHue, tagHue) < 18
      })
    } catch (_) {
      return false
    }
  }

  _angularDistance(a, b) {
    const diff = Math.abs(a - b) % 360
    return Math.min(diff, 360 - diff)
  }

  _parseLinkTagsData() {
    try { return JSON.parse(this.linkTagsDataValue || "{}") } catch (_) { return {} }
  }

  _esc(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
