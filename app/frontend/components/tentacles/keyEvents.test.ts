import { describe, it, expect } from "vitest"

import { keyEventToInputBytes } from "~/components/tentacles/keyEvents"

function ev(overrides: Partial<Parameters<typeof keyEventToInputBytes>[0]> = {}) {
  return {
    key: "Enter",
    shiftKey: false,
    ctrlKey: false,
    altKey: false,
    metaKey: false,
    ...overrides,
  }
}

describe("keyEventToInputBytes", () => {
  it("maps Shift+Enter to ESC+CR so Claude Code treats it as a newline", () => {
    expect(keyEventToInputBytes(ev({ key: "Enter", shiftKey: true }))).toBe("\x1b\r")
  })

  it("returns null for a plain Enter so xterm's default (submit) runs", () => {
    expect(keyEventToInputBytes(ev({ key: "Enter" }))).toBeNull()
  })

  it("returns null for Shift plus a regular character", () => {
    expect(keyEventToInputBytes(ev({ key: "a", shiftKey: true }))).toBeNull()
  })

  it("does not trigger when another modifier is combined with Shift+Enter", () => {
    expect(keyEventToInputBytes(ev({ key: "Enter", shiftKey: true, ctrlKey: true }))).toBeNull()
    expect(keyEventToInputBytes(ev({ key: "Enter", shiftKey: true, altKey: true }))).toBeNull()
    expect(keyEventToInputBytes(ev({ key: "Enter", shiftKey: true, metaKey: true }))).toBeNull()
  })

  it("does not trigger on Alt+Enter alone — xterm already sends ESC+CR natively", () => {
    expect(keyEventToInputBytes(ev({ key: "Enter", altKey: true }))).toBeNull()
  })
})
