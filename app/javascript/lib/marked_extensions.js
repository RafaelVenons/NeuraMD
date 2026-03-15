// Emoji map (common subset)
const EMOJI_MAP = {
  smile: "😊", heart: "❤️", thumbsup: "👍", thumbsdown: "👎",
  fire: "🔥", star: "⭐", check: "✅", x: "❌",
  warning: "⚠️", info: "ℹ️", bulb: "💡", rocket: "🚀",
  tada: "🎉", eyes: "👀", wave: "👋", clap: "👏",
  thinking: "🤔", laugh: "😂", cry: "😢", angry: "😠",
  note: "📝", book: "📚", link: "🔗", lock: "🔒",
  key: "🔑", mail: "📧", phone: "📞", computer: "💻",
  code: "💻", bug: "🐛", sparkles: "✨", zap: "⚡",
}

export const emojiExtension = {
  name: "emoji",
  level: "inline",
  start(src) { return src.indexOf(":") },
  tokenizer(src) {
    const match = /^:([a-z0-9_+\-]+):/.exec(src)
    if (match && EMOJI_MAP[match[1]]) {
      return { type: "emoji", raw: match[0], name: match[1] }
    }
  },
  renderer(token) {
    return EMOJI_MAP[token.name] || token.raw
  }
}

export const superscriptExtension = {
  name: "superscript",
  level: "inline",
  start(src) { return src.indexOf("^") },
  tokenizer(src) {
    const match = /^\^([^\^]+)\^/.exec(src)
    if (match) return { type: "superscript", raw: match[0], text: match[1] }
  },
  renderer(token) {
    return `<sup>${token.text}</sup>`
  }
}

export const subscriptExtension = {
  name: "subscript",
  level: "inline",
  start(src) { return src.indexOf("~") },
  tokenizer(src) {
    const match = /^~([^~]+)~/.exec(src)
    if (match) return { type: "subscript", raw: match[0], text: match[1] }
  },
  renderer(token) {
    return `<sub>${token.text}</sub>`
  }
}

export const highlightExtension = {
  name: "highlight",
  level: "inline",
  start(src) { return src.indexOf("==") },
  tokenizer(src) {
    const match = /^==([^=]+)==/.exec(src)
    if (match) return { type: "highlight", raw: match[0], text: match[1] }
  },
  renderer(token) {
    return `<mark>${token.text}</mark>`
  }
}

// Client-side wiki-link extension for the live preview.
// Converts [[Display Text|uuid]] and [[Display Text|f/c/b:uuid]] to anchor tags.
// Invalid targets are rendered as broken-link spans so raw [[...]] markup never
// leaks into the preview.
const WIKILINK_ROLE_CLASS = { f: "wikilink-father", c: "wikilink-child", b: "wikilink-brother" }
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export const wikilinkExtension = {
  name: "wikilink",
  level: "inline",
  start(src) { return src.indexOf("[[") },
  tokenizer(src) {
    const match = /^\[\[([^\]|]+)\|([fcb]:)?([^\]]+)\]\]/i.exec(src)
    if (match) {
      const target = match[3].trim()
      return {
        type: "wikilink",
        raw: match[0],
        display: match[1].trim(),
        role: match[2] ? match[2].replace(":", "") : null,
        uuid: UUID_RE.test(target) ? target.toLowerCase() : null
      }
    }
  },
  renderer(token) {
    const display   = token.display.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    if (!token.uuid) {
      return `<span class="wikilink-broken" title="Nota nao encontrada">${display}</span>`
    }
    const roleClass = WIKILINK_ROLE_CLASS[token.role] || "wikilink-null"
    return `<a href="/notes/${token.uuid}" class="wikilink ${roleClass}" data-uuid="${token.uuid}">${display}</a>`
  }
}
