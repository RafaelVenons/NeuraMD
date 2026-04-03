import { getEmojiMap } from "lib/emoji_data"

// Full emoji map loaded from emoji_data.js
const EMOJI_MAP = getEmojiMap()

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
// Converts resolved [[Display Text|uuid]], [[Display Text|f:uuid]],
// [[Display Text|c:uuid]] and [[Display Text|b:uuid]] to
// anchors, and unresolved [[Future Note]] references to promise spans.
// Invalid targets are rendered as broken-link spans so raw [[...]] markup never
// leaks into the preview.
const WIKILINK_ROLE_CLASS = { f: "wikilink-father", c: "wikilink-child", b: "wikilink-brother" }
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export const wikilinkExtension = {
  name: "wikilink",
  level: "inline",
  start(src) {
    let idx = 0
    while (true) {
      const pos = src.indexOf("[[", idx)
      if (pos < 0) return -1
      if (pos === 0 || src[pos - 1] !== "!") return pos
      idx = pos + 2
    }
  },
  tokenizer(src) {
    const match = /^\[\[([^\]|]+)\|(?:([a-z]+):)?([^\]]+)\]\]/i.exec(src)
    if (match) {
      const target = match[3].trim()
      let uuidPart, headingSlug = null, blockId = null
      if (target.includes("^")) {
        const parts = target.split("^")
        uuidPart = parts[0]
        blockId = parts[1] || null
      } else {
        const [first, ...rest] = target.split("#")
        uuidPart = first
        headingSlug = rest.join("#") || null
      }
      return {
        type: "wikilink",
        raw: match[0],
        display: match[1].trim(),
        role: match[2] ? match[2].replace(":", "") : null,
        uuid: UUID_RE.test(uuidPart) ? uuidPart.toLowerCase() : null,
        headingSlug,
        blockId
      }
    }

    const promiseMatch = /^\[\[([^\]\|]+)\]\]/i.exec(src)
    if (promiseMatch) {
      return {
        type: "wikilink",
        raw: promiseMatch[0],
        display: promiseMatch[1].trim(),
        role: null,
        uuid: null,
        promise: true
      }
    }
  },
  renderer(token) {
    const display   = token.display.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    if (token.promise) {
      return `<span class="wikilink-promise" title="Sugestao de nota futura">${display}</span>`
    }
    if (!token.uuid) {
      return `<span class="wikilink-broken" title="Nota nao encontrada">${display}</span>`
    }
    const roleClass = WIKILINK_ROLE_CLASS[token.role] || "wikilink-null"
    const fragment = token.headingSlug ? `#${token.headingSlug}` : token.blockId ? `#${token.blockId}` : ""
    const fragAttr = token.headingSlug ? ` data-heading-slug="${token.headingSlug}"` : token.blockId ? ` data-block-id="${token.blockId}"` : ""
    return `<a href="/notes/${token.uuid}${fragment}" class="wikilink ${roleClass}" data-uuid="${token.uuid}"${fragAttr}>${display}</a>`
  }
}

function encodeMathSource(text) {
  return text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function escapeMathHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

export const mathBlockExtension = {
  name: "mathBlock",
  level: "block",
  start(src) { return src.indexOf("$$") },
  tokenizer(src) {
    const match = /^\$\$\n?([\s\S]+?)\n?\$\$/.exec(src)
    if (match) return { type: "mathBlock", raw: match[0], text: match[1].trim() }
  },
  renderer(token) {
    return `<div class="math-block" data-math="${encodeMathSource(token.text)}">${escapeMathHtml(token.text)}</div>\n`
  }
}

export const mathInlineExtension = {
  name: "mathInline",
  level: "inline",
  start(src) {
    const idx = src.indexOf("$")
    if (idx < 0) return -1
    // Skip $$ (handled by block extension)
    if (src[idx + 1] === "$") return -1
    return idx
  },
  tokenizer(src) {
    // Match $..$ but not $$..$$, and require non-space after opening $
    const match = /^\$([^\$\n]+?)\$/.exec(src)
    if (match && match[1][0] !== " " && match[1][match[1].length - 1] !== " ") {
      return { type: "mathInline", raw: match[0], text: match[1] }
    }
  },
  renderer(token) {
    return `<span class="math-inline" data-math="${encodeMathSource(token.text)}">${escapeMathHtml(token.text)}</span>`
  }
}

export const embedExtension = {
  name: "embed",
  level: "block",
  start(src) { return src.indexOf("![[") },
  tokenizer(src) {
    const match = /^!\[\[([^\]|]+)\|(?:([a-z]+):)?([^\]#^]+)(?:#([a-z0-9_-]+)|\^([a-zA-Z0-9-]+))?\]\]\n?/i.exec(src)
    if (!match) return
    const uuidPart = match[3].trim()
    if (!UUID_RE.test(uuidPart)) return
    return {
      type: "embed",
      raw: match[0],
      display: match[1].trim(),
      role: match[2] || null,
      uuid: uuidPart.toLowerCase(),
      headingSlug: match[4] || null,
      blockId: match[5] || null
    }
  },
  renderer(token) {
    const display = token.display.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    const dataHeading = token.headingSlug ? ` data-embed-heading="${token.headingSlug}"` : ""
    const dataBlock = token.blockId ? ` data-embed-block="${token.blockId}"` : ""
    return `<div class="embed-container embed-loading" data-embed-uuid="${token.uuid}"${dataHeading}${dataBlock}>`
      + `<div class="embed-header">${display}</div>`
      + `<div class="embed-content"><span class="embed-spinner">Carregando...</span></div>`
      + `</div>\n`
  }
}
