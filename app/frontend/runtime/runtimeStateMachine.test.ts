import { describe, it, expect } from "vitest"

import {
  type RuntimeEvent,
  type RuntimeState,
  deriveStateFromEvent,
} from "~/runtime/runtimeStateMachine"

const step = (prev: RuntimeState | null, event: RuntimeEvent) =>
  deriveStateFromEvent(prev, event)

describe("deriveStateFromEvent", () => {
  it("promotes a fresh terminal to processing on input", () => {
    expect(step(null, { type: "input" })).toBe("processing")
  })

  it("promotes a fresh terminal to processing on output", () => {
    expect(step(null, { type: "output" })).toBe("processing")
  })

  it("stays idle when silence hits a terminal with no prior activity", () => {
    expect(step(null, { type: "silence" })).toBe("idle")
  })

  it("flips processing to needs_input on silence", () => {
    expect(step("processing", { type: "silence" })).toBe("needs_input")
  })

  it("keeps idle unchanged on silence", () => {
    expect(step("idle", { type: "silence" })).toBe("idle")
  })

  it("keeps needs_input unchanged on silence so the badge does not flicker", () => {
    expect(step("needs_input", { type: "silence" })).toBe("needs_input")
  })

  it("returns to processing when the user types after needs_input", () => {
    expect(step("needs_input", { type: "input" })).toBe("processing")
  })

  it("returns to processing when the agent emits output after needs_input", () => {
    expect(step("needs_input", { type: "output" })).toBe("processing")
  })

  it("marks exited on explicit exit regardless of prior state", () => {
    for (const prev of ["idle", "processing", "needs_input"] as const) {
      expect(step(prev, { type: "exit" })).toBe("exited")
    }
    expect(step(null, { type: "exit" })).toBe("exited")
  })

  it("leaves exited on activity so a restarted session can recover its badge", () => {
    expect(step("exited", { type: "input" })).toBe("processing")
    expect(step("exited", { type: "output" })).toBe("processing")
  })

  it("keeps exited on silence so a dead session does not flicker back to life", () => {
    expect(step("exited", { type: "silence" })).toBe("exited")
  })

  it("keeps exited on repeated exit events", () => {
    expect(step("exited", { type: "exit" })).toBe("exited")
  })
})
