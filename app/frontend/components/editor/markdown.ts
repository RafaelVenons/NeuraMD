import { Marked, type MarkedExtension, type Tokens } from "marked"
import { markedHighlight } from "marked-highlight"
import hljs from "highlight.js/lib/common"
import katex from "katex"

type WikilinkToken = Tokens.Generic & {
  type: "wikilink"
  raw: string
  display: string
  role: string | null
  target: string
}

type MathToken = Tokens.Generic & {
  type: "inlineMath" | "blockMath"
  raw: string
  text: string
}

const wikilinkExtension: MarkedExtension = {
  extensions: [
    {
      name: "wikilink",
      level: "inline",
      start(src) {
        return src.indexOf("[[")
      },
      tokenizer(src): WikilinkToken | undefined {
        const match = /^\[\[([^\]]+)\]\]/.exec(src)
        if (!match) return undefined
        const body = match[1] ?? ""
        const pipeIdx = body.indexOf("|")
        const display = pipeIdx === -1 ? body : body.slice(0, pipeIdx)
        const tail = pipeIdx === -1 ? null : body.slice(pipeIdx + 1)
        let role: string | null = null
        let target: string = tail ?? display
        if (tail) {
          const colonIdx = tail.indexOf(":")
          if (colonIdx !== -1) {
            role = tail.slice(0, colonIdx)
            target = tail.slice(colonIdx + 1)
          }
        }
        return {
          type: "wikilink",
          raw: match[0],
          display,
          role,
          target,
        }
      },
      renderer(token) {
        const t = token as WikilinkToken
        const encoded = encodeURIComponent(t.target)
        const role = t.role ? ` data-role="${escapeAttribute(t.role)}"` : ""
        return `<a class="nm-wikilink" href="/app/notes/${encoded}"${role}>${escapeHtml(t.display)}</a>`
      },
    },
  ],
}

const blockMathExtension: MarkedExtension = {
  extensions: [
    {
      name: "blockMath",
      level: "block",
      start(src) {
        return src.indexOf("$$")
      },
      tokenizer(src): MathToken | undefined {
        const match = /^\$\$([\s\S]+?)\$\$(?:\n|$)/.exec(src)
        if (!match) return undefined
        return {
          type: "blockMath",
          raw: match[0],
          text: (match[1] ?? "").trim(),
        }
      },
      renderer(token) {
        const t = token as MathToken
        try {
          return `<div class="nm-math nm-math--block">${katex.renderToString(t.text, { displayMode: true, throwOnError: false })}</div>`
        } catch {
          return `<pre class="nm-math-error">${escapeHtml(t.text)}</pre>`
        }
      },
    },
  ],
}

const inlineMathExtension: MarkedExtension = {
  extensions: [
    {
      name: "inlineMath",
      level: "inline",
      start(src) {
        return src.indexOf("$")
      },
      tokenizer(src): MathToken | undefined {
        const match = /^\$(?!\$)([^\n$]+?)\$/.exec(src)
        if (!match) return undefined
        return {
          type: "inlineMath",
          raw: match[0],
          text: (match[1] ?? "").trim(),
        }
      },
      renderer(token) {
        const t = token as MathToken
        try {
          return `<span class="nm-math nm-math--inline">${katex.renderToString(t.text, { displayMode: false, throwOnError: false })}</span>`
        } catch {
          return `<code class="nm-math-error">${escapeHtml(t.text)}</code>`
        }
      },
    },
  ],
}

const marked = new Marked(
  markedHighlight({
    langPrefix: "hljs language-",
    highlight(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        return hljs.highlight(code, { language: lang }).value
      }
      return hljs.highlightAuto(code).value
    },
  }),
  wikilinkExtension,
  blockMathExtension,
  inlineMathExtension,
  { gfm: true, breaks: false }
)

export function renderMarkdown(markdown: string): string {
  return marked.parse(markdown || "", { async: false }) as string
}

function escapeHtml(input: string): string {
  return input
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function escapeAttribute(input: string): string {
  return input.replace(/"/g, "&quot;")
}
