import { describe, it, expect } from "vitest"

import { renderMarkdown } from "~/components/editor/markdown"

describe("renderMarkdown sanitization", () => {
  it("strips inline event handlers from raw HTML", () => {
    const html = renderMarkdown('<img src=x onerror="alert(1)">')
    expect(html).not.toMatch(/onerror/i)
    expect(html).not.toMatch(/alert\(1\)/)
  })

  it("drops <script> tags entirely", () => {
    const html = renderMarkdown("<script>alert('xss')</script>\n\nparagraph")
    expect(html).not.toMatch(/<script/i)
    expect(html).not.toMatch(/alert/)
    expect(html).toMatch(/paragraph/)
  })

  it("blocks javascript: URLs in markdown links", () => {
    const html = renderMarkdown("[click](javascript:alert(1))")
    expect(html).not.toMatch(/javascript:/i)
  })

  it("blocks javascript: URLs in raw anchor tags", () => {
    const html = renderMarkdown('<a href="javascript:alert(1)">x</a>')
    expect(html).not.toMatch(/javascript:/i)
  })

  it("removes <iframe> elements", () => {
    const html = renderMarkdown('<iframe src="https://evil.test"></iframe>')
    expect(html).not.toMatch(/<iframe/i)
  })

  it("removes <object> and <embed> elements", () => {
    const html = renderMarkdown('<object data="x"></object><embed src="y">')
    expect(html).not.toMatch(/<object/i)
    expect(html).not.toMatch(/<embed/i)
  })

  it("strips style attributes that can execute script-like behaviour", () => {
    const html = renderMarkdown('<p onclick="steal()">hi</p>')
    expect(html).not.toMatch(/onclick/i)
    expect(html).toMatch(/hi/)
  })
})

describe("renderMarkdown preserves trusted markdown output", () => {
  it("keeps wikilink anchors with data-role attribute", () => {
    const html = renderMarkdown("[[Editor|c:abc-123]]")
    expect(html).toMatch(/class="nm-wikilink"/)
    expect(html).toMatch(/data-role="c"/)
    expect(html).toMatch(/href="\/app\/notes\/abc-123"/)
  })

  it("renders fenced code blocks with hljs classes", () => {
    const html = renderMarkdown("```ruby\nputs 'hi'\n```")
    expect(html).toMatch(/class="hljs language-ruby"/)
    expect(html).toMatch(/puts/)
  })

  it("renders inline math via KaTeX spans", () => {
    const html = renderMarkdown("inline $x^2$ math")
    expect(html).toMatch(/class="nm-math nm-math--inline"/)
    expect(html).toMatch(/class="katex"/)
  })

  it("renders block math via KaTeX div", () => {
    const html = renderMarkdown("$$\\int_0^1 x\\,dx$$\n")
    expect(html).toMatch(/class="nm-math nm-math--block"/)
    expect(html).toMatch(/class="katex"/)
  })

  it("renders GFM tables", () => {
    const html = renderMarkdown("| a | b |\n|---|---|\n| 1 | 2 |\n")
    expect(html).toMatch(/<table/)
    expect(html).toMatch(/<thead/)
  })
})
