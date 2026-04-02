export class ColorPicker {
  constructor(elements, callbacks) {
    this._el = elements
    this._cb = callbacks
    this._currentWheelHue = 216
  }

  get currentWheelHue() { return this._currentWheelHue }
  set currentWheelHue(val) { this._currentWheelHue = val }

  open(anchorRect) {
    const popup = this._el.picker
    const spaceBelow = window.innerHeight - anchorRect.top
    popup.style.left = (anchorRect.right + 8) + "px"
    if (spaceBelow < 280) {
      popup.style.bottom = (window.innerHeight - anchorRect.bottom) + "px"
      popup.style.top = "auto"
    } else {
      popup.style.top = anchorRect.top + "px"
      popup.style.bottom = "auto"
    }

    popup.hidden = false
    this._renderSuggestions()
    this._drawWheel()
    this._updateCustomPreview()
  }

  close() {
    if (this._el.picker) this._el.picker.hidden = true
  }

  isOpen() {
    return this._el.picker && !this._el.picker.hidden
  }

  selectColor(hex) {
    this._cb.onColorSelected(hex)
    this.close()
  }

  confirmCustomColor() {
    const hex = this._hslToHex(this._currentWheelHue, 75, 60)
    this.selectColor(hex)
  }

  onWheelClick(e) {
    const hue = this._hueFromWheelEvent(e)
    if (hue === null) return
    this._currentWheelHue = hue
    const hex = this._hslToHex(hue, 75, 60)
    this._cb.onWheelColorChanged(hex)
    this._updateCustomPreview()
    this._drawWheel()
  }

  onWheelHover(e) {
    const hue = this._hueFromWheelEvent(e)
    if (hue === null) return
    this._drawWheel(hue)
  }

  suggestNextColor() {
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

  setHueFromHex(hex) {
    try {
      const [hue] = this._hexToHsl(hex)
      this._currentWheelHue = hue
    } catch (_) {}
  }

  // ── Rendering ────────────────────────────────────────────

  _renderSuggestions() {
    const suggestions = this._generateSuggestions()
    this._el.suggestions.innerHTML = suggestions.map(hex => {
      const wcag = this._contrastOnDark(hex)
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

  _updateCustomPreview() {
    if (!this._el.preview) return
    const hex = this._hslToHex(this._currentWheelHue, 75, 60)
    const wcag = this._contrastOnDark(hex)

    this._el.preview.style.background = hex
    this._el.hex.textContent = hex
    this._el.wcag.textContent = wcag
    this._el.wcag.className =
      `tcp-wcag tcp-wcag--${wcag === "FAIL" ? "fail" : wcag.startsWith("AAA") ? "aaa" : "aa"}`
  }

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

    const nextColor = this.suggestNextColor()
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

  // ── Color wheel ──────────────────────────────────────────

  _drawWheel(hoverHue = null) {
    if (!this._el.wheel) return
    const canvas = this._el.wheel
    const ctx = canvas.getContext("2d")
    const SIZE = 156, CX = 78, CY = 78, R = 72, IR = 38

    ctx.clearRect(0, 0, SIZE, SIZE)

    for (let angle = 0; angle < 360; angle += 0.5) {
      const r1 = (angle - 90) * Math.PI / 180
      const r2 = (angle + 0.6 - 90) * Math.PI / 180
      ctx.beginPath()
      ctx.moveTo(CX + IR * Math.cos(r1), CY + IR * Math.sin(r1))
      ctx.lineTo(CX + R * Math.cos(r1), CY + R * Math.sin(r1))
      ctx.lineTo(CX + R * Math.cos(r2), CY + R * Math.sin(r2))
      ctx.lineTo(CX + IR * Math.cos(r2), CY + IR * Math.sin(r2))
      ctx.closePath()
      ctx.fillStyle = `hsl(${angle}, 75%, 60%)`
      ctx.fill()
    }

    const midR = (R + IR) / 2

    if (hoverHue !== null && hoverHue !== this._currentWheelHue) {
      const hRad = (hoverHue - 90) * Math.PI / 180
      const hx = CX + midR * Math.cos(hRad)
      const hy = CY + midR * Math.sin(hRad)
      ctx.beginPath()
      ctx.arc(hx, hy, 5, 0, Math.PI * 2)
      ctx.fillStyle = `hsla(${hoverHue}, 75%, 60%, 0.55)`
      ctx.fill()
      ctx.strokeStyle = "rgba(255,255,255,0.4)"
      ctx.lineWidth = 1.5
      ctx.stroke()
    }

    const selRad = (this._currentWheelHue - 90) * Math.PI / 180
    const sx = CX + midR * Math.cos(selRad)
    const sy = CY + midR * Math.sin(selRad)
    ctx.beginPath()
    ctx.arc(sx, sy, 7, 0, Math.PI * 2)
    ctx.fillStyle = this._hslToHex(this._currentWheelHue, 75, 60)
    ctx.fill()
    ctx.strokeStyle = "white"
    ctx.lineWidth = 2
    ctx.stroke()
  }

  _hueFromWheelEvent(e) {
    if (!this._el.wheel) return null
    const canvas = this._el.wheel
    const rect = canvas.getBoundingClientRect()
    const scaleX = 156 / rect.width
    const scaleY = 156 / rect.height
    const x = (e.clientX - rect.left) * scaleX - 78
    const y = (e.clientY - rect.top) * scaleY - 78
    const dist = Math.sqrt(x * x + y * y)
    if (dist < 38 || dist > 72) return null
    let hue = Math.atan2(y, x) * 180 / Math.PI + 90
    if (hue < 0) hue += 360
    return Math.round(hue) % 360
  }

  // ── Color math ───────────────────────────────────────────

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

  // ── Palette analysis ─────────────────────────────────────

  _dominantTagColors() {
    const { tags, tagUsage } = this._cb.getTagData()

    const ranked = tags
      .filter(tag => tag.color_hex)
      .map(tag => ({
        hue: this._hexToHsl(tag.color_hex)[0],
        weight: tagUsage[tag.id] || 0
      }))
      .filter(entry => entry.weight > 0)
      .sort((a, b) => b.weight - a.weight)

    if (ranked.length) return ranked.slice(0, 6)

    return tags
      .filter(tag => tag.color_hex)
      .slice(-6)
      .map(tag => ({ hue: this._hexToHsl(tag.color_hex)[0], weight: 1 }))
  }

  _hasSimilarTagColor(hex) {
    try {
      const [candidateHue] = this._hexToHsl(hex)
      const { tags } = this._cb.getTagData()
      return tags.some(tag => {
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

  _esc(str) {
    return (str || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
