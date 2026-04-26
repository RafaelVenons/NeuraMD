import { describe, expect, it } from "vitest"
import { renderToStaticMarkup } from "react-dom/server"
import type { JSX } from "react"

import { ClawdAvatar } from "~/components/graph/ClawdAvatar"

const wrap = (svgInner: JSX.Element) =>
  renderToStaticMarkup(
    <svg width={64} height={64} viewBox="-32 -32 64 64">
      {svgInner}
    </svg>
  )

describe("ClawdAvatar", () => {
  it("renders awake eyes by default", () => {
    const html = wrap(<ClawdAvatar state="awake" color="#fff" />)
    expect(html).toContain('data-testid="clawd-eyes-awake"')
    expect(html).not.toContain('data-testid="clawd-eyes-sleeping"')
  })

  it("renders sleeping eyes and the Zzz when state is sleeping", () => {
    const html = wrap(<ClawdAvatar state="sleeping" color="#fff" />)
    expect(html).toContain('data-testid="clawd-eyes-sleeping"')
    expect(html).toContain('data-testid="clawd-zzz"')
  })

  it("omits hat decoration when hat is none", () => {
    const html = wrap(<ClawdAvatar state="awake" color="#fff" hat="none" />)
    expect(html).not.toContain('data-testid="clawd-hat-cartola"')
    expect(html).not.toContain('data-testid="clawd-hat-chef"')
  })

  it("renders the cartola hat when requested", () => {
    const html = wrap(<ClawdAvatar state="awake" color="#fff" hat="cartola" />)
    expect(html).toContain('data-testid="clawd-hat-cartola"')
  })

  it("renders the chef hat when requested", () => {
    const html = wrap(<ClawdAvatar state="awake" color="#fff" hat="chef" />)
    expect(html).toContain('data-testid="clawd-hat-chef"')
  })

  it("adds the nm-clawd-zzz class only when animateZzz is true and state is sleeping", () => {
    const animated = wrap(<ClawdAvatar state="sleeping" color="#fff" animateZzz />)
    expect(animated).toContain('class="nm-clawd-zzz"')

    const stable = wrap(<ClawdAvatar state="sleeping" color="#fff" />)
    expect(stable).not.toContain('class="nm-clawd-zzz"')
  })

  it("uses the provided color for the body fill", () => {
    const html = wrap(<ClawdAvatar state="awake" color="#abcdef" />)
    expect(html).toContain('fill="#abcdef"')
  })
})
