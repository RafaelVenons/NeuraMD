import { Controller } from "@hotwired/stimulus"
import { EMOJI_DATA } from "lib/emoji_data"

const EMOTICON_DATA = [
  // Happy & Positive
  ["happy", "(◕‿◕)", "smile joy"],
  ["excited", "(ﾉ◕ヮ◕)ﾉ*:・ﾟ✧", "joy sparkle celebrate"],
  ["very_happy", "(✿◠‿◠)", "smile flower cute"],
  ["joyful", "(*^▽^*)", "happy grin"],
  ["cheerful", "(｡◕‿◕｡)", "happy cute"],
  ["wink", "(^_~)", "flirt playful"],
  ["peace", "(￣▽￣)ノ", "wave hello"],

  // Love & Affection
  ["love", "(♥‿♥)", "heart eyes adore"],
  ["hearts", "(｡♥‿♥｡)", "love adore"],
  ["hug", "(つ≧▽≦)つ", "embrace love"],
  ["kiss", "(＾3＾)～♡", "love smooch"],
  ["blushing", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", "shy embarrassed"],

  // Sad & Upset
  ["sad", "(´;ω;`)", "cry tears"],
  ["crying", "(╥﹏╥)", "tears upset"],
  ["disappointed", "(´･_･`)", "sad down"],

  // Angry & Frustrated
  ["angry", "(╬ Ò﹏Ó)", "mad rage"],
  ["table_flip", "(╯°□°)╯︵ ┻━┻", "angry flip rage"],
  ["put_table_back", "┬─┬ノ( º _ ºノ)", "calm restore"],
  ["grumpy", "(¬_¬)", "annoyed side eye"],

  // Surprised
  ["surprised", "(°o°)", "shock wow"],
  ["shocked", "Σ(°△°|||)", "surprise wow"],

  // Confused
  ["confused", "(・・?)", "puzzled question"],
  ["thinking", "(￢_￢)", "ponder hmm"],
  ["shrug", "¯\\_(ツ)_/¯", "whatever idk"],

  // Cute & Kawaii
  ["cat", "(=^・ω・^=)", "neko meow"],
  ["bear", "ʕ•ᴥ•ʔ", "animal cute"],
  ["bunny", "(・x・)", "rabbit animal"],
  ["dog", "▼・ᴥ・▼", "puppy animal"],
  ["flower", "(✿´‿`)", "cute happy"],

  // Actions
  ["look_away", "(눈_눈)", "suspicious stare"],
  ["hide", "|ω・)", "peek shy"],
  ["running", "ε=ε=ε=┌(;*´Д`)ﾉ", "run escape"],
  ["dancing", "♪(´ε` )", "music happy"],
  ["sleeping", "(－_－) zzZ", "tired sleep"],
  ["fighting", "(ง •̀_•́)ง", "fight strong"],

  // Special
  ["lenny", "( ͡° ͜ʖ ͡°)", "meme suspicious"],
  ["disapproval", "ಠ_ಠ", "stare judge"],
  ["cool", "(⌐■_■)", "sunglasses awesome"],
  ["thumbs_up", "(b ᵔ▽ᵔ)b", "approve good"],
  ["bow", "m(_ _)m", "thanks sorry respect"],
  ["hello", "(・ω・)ノ", "wave hi"],
  ["magic", "(ノ°∀°)ノ⌒・*:.。. .。.:*・゜゚・*", "sparkle star"],
  ["wizard", "(∩｀-´)⊃━☆ﾟ.*･｡ﾟ", "magic spell"]
]

export default class extends Controller {
  static targets = [
    "dialog",
    "input",
    "grid",
    "preview",
    "tabEmoji",
    "tabEmoticons"
  ]

  static values = {
    columns: { type: Number, default: 10 },
    emoticonColumns: { type: Number, default: 5 }
  }

  connect() {
    this.allEmojis = EMOJI_DATA
    this.allEmoticons = EMOTICON_DATA
    this.filteredItems = [...this.allEmojis]
    this.selectedIndex = 0
    this.activeTab = "emoji"
  }

  open() {
    this.activeTab = "emoji"
    this.filteredItems = [...this.allEmojis]
    this.selectedIndex = 0
    this.inputTarget.value = ""
    this.updateTabStyles()
    this.renderGrid()
    this.updatePreview()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  switchToEmoji() {
    if (this.activeTab === "emoji") return
    this.activeTab = "emoji"
    this.selectedIndex = 0
    this.updateTabStyles()
    this.onInput()
  }

  switchToEmoticons() {
    if (this.activeTab === "emoticons") return
    this.activeTab = "emoticons"
    this.selectedIndex = 0
    this.updateTabStyles()
    this.onInput()
  }

  updateTabStyles() {
    if (!this.hasTabEmojiTarget || !this.hasTabEmoticonsTarget) return

    const active = this.activeTab === "emoji" ? this.tabEmojiTarget : this.tabEmoticonsTarget
    const inactive = this.activeTab === "emoji" ? this.tabEmoticonsTarget : this.tabEmojiTarget

    active.style.background = "var(--theme-accent)"
    active.style.color = "var(--theme-accent-text)"
    inactive.style.background = "transparent"
    inactive.style.color = "var(--theme-text-muted)"
  }

  onInput() {
    const query = this.inputTarget.value.trim().toLowerCase()
    const sourceData = this.activeTab === "emoji" ? this.allEmojis : this.allEmoticons

    if (!query) {
      this.filteredItems = [...sourceData]
    } else {
      this.filteredItems = sourceData.filter(([name, , keywords]) => {
        const searchText = `${name} ${keywords}`.toLowerCase()
        return query.split(/\s+/).every(term => searchText.includes(term))
      })
    }

    this.selectedIndex = 0
    this.renderGrid()
    this.updatePreview()
  }

  getCurrentColumns() {
    return this.activeTab === "emoji" ? this.columnsValue : this.emoticonColumnsValue
  }

  renderGrid() {
    const cols = this.getCurrentColumns()

    if (this.filteredItems.length === 0) {
      this.gridTarget.innerHTML = `
        <div class="col-span-full px-3 py-6 text-center text-sm" style="color: var(--theme-text-muted);">
          Nenhum resultado encontrado
        </div>
      `
      this.gridTarget.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
      return
    }

    if (this.activeTab === "emoji") {
      this._renderEmojiGrid()
    } else {
      this._renderEmoticonGrid()
    }

    this.gridTarget.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
    this._scrollSelectedIntoView()
  }

  _renderEmojiGrid() {
    this.gridTarget.innerHTML = this.filteredItems
      .map(([shortcode, emoji], index) => {
        const sel = index === this.selectedIndex
          ? "background: var(--theme-accent); box-shadow: 0 0 0 2px var(--theme-accent);"
          : ""
        return `
          <button type="button"
            class="w-10 h-10 flex items-center justify-center text-2xl rounded cursor-pointer"
            style="${sel}"
            data-index="${index}"
            data-shortcode="${this._esc(shortcode)}"
            data-action="click->emoji-picker#selectFromClick mouseenter->emoji-picker#onHover"
            title=":${this._esc(shortcode)}:"
          >${emoji}</button>
        `
      })
      .join("")
  }

  _renderEmoticonGrid() {
    this.gridTarget.innerHTML = this.filteredItems
      .map(([name, emoticon], index) => {
        const sel = index === this.selectedIndex
          ? "background: var(--theme-accent); color: var(--theme-accent-text); box-shadow: 0 0 0 2px var(--theme-accent);"
          : "color: var(--theme-text-primary);"
        return `
          <button type="button"
            class="px-2 py-2 flex items-center justify-center text-sm rounded truncate cursor-pointer"
            style="${sel}"
            data-index="${index}"
            data-emoticon="${this._esc(emoticon)}"
            data-action="click->emoji-picker#selectFromClick mouseenter->emoji-picker#onHover"
            title="${this._esc(name)}"
          >${this._esc(emoticon)}</button>
        `
      })
      .join("")
  }

  _scrollSelectedIntoView() {
    const el = this.gridTarget.querySelector(`[data-index="${this.selectedIndex}"]`)
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  updatePreview() {
    if (!this.hasPreviewTarget || this.filteredItems.length === 0) {
      if (this.hasPreviewTarget) this.previewTarget.innerHTML = ""
      return
    }

    const [name, display] = this.filteredItems[this.selectedIndex] || []
    if (!name) return

    if (this.activeTab === "emoji") {
      this.previewTarget.innerHTML = `
        <span class="text-4xl">${display}</span>
        <code class="text-sm px-2 py-1 rounded" style="background: var(--theme-bg-tertiary);">:${this._esc(name)}:</code>
      `
    } else {
      this.previewTarget.innerHTML = `
        <span class="text-lg font-mono">${this._esc(display)}</span>
        <span class="text-sm" style="color: var(--theme-text-muted);">${this._esc(name)}</span>
      `
    }
  }

  onKeydown(event) {
    const cols = this.getCurrentColumns()
    const total = this.filteredItems.length
    if (total === 0) return

    switch (event.key) {
      case "ArrowRight":
        event.preventDefault()
        this.selectedIndex = (this.selectedIndex + 1) % total
        break
      case "ArrowLeft":
        event.preventDefault()
        this.selectedIndex = (this.selectedIndex - 1 + total) % total
        break
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = (this.selectedIndex + cols < total)
          ? this.selectedIndex + cols
          : Math.min(this.selectedIndex % cols, total - 1)
        break
      case "ArrowUp":
        event.preventDefault()
        if (this.selectedIndex - cols >= 0) {
          this.selectedIndex -= cols
        } else {
          const col = this.selectedIndex % cols
          const lastRowStart = Math.floor((total - 1) / cols) * cols
          this.selectedIndex = Math.min(lastRowStart + col, total - 1)
        }
        break
      case "Enter":
        event.preventDefault()
        this._selectCurrent()
        return
      case "Escape":
        return
      default:
        return
    }
    this.renderGrid()
    this.updatePreview()
  }

  onHover(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (!isNaN(index) && index !== this.selectedIndex) {
      this.selectedIndex = index
      this.renderGrid()
      this.updatePreview()
    }
  }

  selectFromClick(event) {
    if (this.activeTab === "emoji") {
      const shortcode = event.currentTarget.dataset.shortcode
      if (shortcode) this._dispatchSelected(`:${shortcode}:`)
    } else {
      const emoticon = event.currentTarget.dataset.emoticon
      if (emoticon) this._dispatchSelected(emoticon)
    }
  }

  _selectCurrent() {
    if (this.filteredItems.length === 0) return
    const [name, display] = this.filteredItems[this.selectedIndex] || []
    if (!name) return

    if (this.activeTab === "emoji") {
      this._dispatchSelected(`:${name}:`)
    } else {
      this._dispatchSelected(display)
    }
  }

  _dispatchSelected(text) {
    this.dispatch("selected", {
      detail: { text, type: this.activeTab },
      bubbles: true
    })
    this.close()
  }

  _esc(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
