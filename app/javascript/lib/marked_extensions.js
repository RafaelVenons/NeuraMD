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
