import { Controller } from "@hotwired/stimulus"

const THEMES = [
  { id: "dark",           name: "Dark",           icon: "moon" },
  { id: "light",          name: "Light",          icon: "sun" },
  { id: "nord",           name: "Nord",           icon: "palette" },
  { id: "rose-pine",      name: "Rosé Pine",      icon: "palette" },
  { id: "tokyo-night",    name: "Tokyo Night",    icon: "palette" },
  { id: "solarized-dark", name: "Solarized Dark", icon: "palette" },
  { id: "gruvbox",        name: "Gruvbox",        icon: "palette" },
  { id: "catppuccin",     name: "Catppuccin",     icon: "palette" }
]

const LIGHT_THEMES = new Set(["light"])
const STORAGE_KEY = "neuramd-theme"

const ICONS = {
  sun: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>`,
  moon: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2"><path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/></svg>`,
  palette: `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2"><circle cx="13.5" cy="6.5" r="0.5" fill="currentColor"/><circle cx="17.5" cy="10.5" r="0.5" fill="currentColor"/><circle cx="8.5" cy="7.5" r="0.5" fill="currentColor"/><circle cx="6.5" cy="12" r="0.5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 011.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.555C21.965 6.012 17.461 2 12 2z"/></svg>`,
  check: `<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="3"><polyline points="20 6 9 17 4 12"/></svg>`
}

export default class extends Controller {
  static targets = ["menu", "currentTheme"]

  connect() {
    this._open = false
    this._closeHandler = (e) => {
      if (!this.element.contains(e.target)) this._hideMenu()
    }

    const saved = localStorage.getItem(STORAGE_KEY) || "dark"
    this._applyTheme(saved)
  }

  toggle() {
    this._open ? this._hideMenu() : this._showMenu()
  }

  select(event) {
    const themeId = event.currentTarget.dataset.themeId
    if (!themeId) return
    this._applyTheme(themeId)
    localStorage.setItem(STORAGE_KEY, themeId)
    this._hideMenu()
  }

  _applyTheme(themeId) {
    document.documentElement.setAttribute("data-theme", themeId)
    document.documentElement.classList.toggle("dark", !LIGHT_THEMES.has(themeId))

    if (this.hasCurrentThemeTarget) {
      const theme = THEMES.find(t => t.id === themeId)
      this.currentThemeTarget.textContent = theme?.name || themeId
    }

    this._currentTheme = themeId
  }

  _showMenu() {
    this._open = true
    this._renderMenu()
    this.menuTarget.classList.remove("hidden")
    setTimeout(() => document.addEventListener("click", this._closeHandler), 0)
  }

  _hideMenu() {
    this._open = false
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this._closeHandler)
  }

  _renderMenu() {
    this.menuTarget.innerHTML = THEMES.map(theme => {
      const isCurrent = theme.id === this._currentTheme
      return `
        <button type="button"
                class="w-full px-3 py-1.5 text-left text-sm flex items-center gap-2 cursor-pointer"
                style="color: var(--theme-text-primary);"
                onmouseover="this.style.background='var(--theme-bg-hover)'"
                onmouseout="this.style.background='transparent'"
                data-theme-id="${theme.id}"
                data-action="click->theme#select">
          ${ICONS[theme.icon]}
          <span class="flex-1">${theme.name}</span>
          ${isCurrent ? ICONS.check : '<span class="w-3 h-3"></span>'}
        </button>
      `
    }).join("")
  }
}
