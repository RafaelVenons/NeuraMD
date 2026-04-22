import { describe, it, expect, vi } from "vitest"

import { createRuntimeStateStore } from "~/runtime/runtimeStateStore"

describe("createRuntimeStateStore", () => {
  it("starts empty", () => {
    const store = createRuntimeStateStore()
    expect(store.getSnapshot()).toEqual({})
  })

  it("records a state entry with the supplied timestamp", () => {
    const store = createRuntimeStateStore()
    store.setState("t1", "processing", 1234)
    expect(store.getSnapshot()).toEqual({ t1: { state: "processing", at: 1234 } })
  })

  it("returns a new snapshot reference when state changes", () => {
    const store = createRuntimeStateStore()
    const before = store.getSnapshot()
    store.setState("t1", "processing", 1)
    const after = store.getSnapshot()
    expect(after).not.toBe(before)
  })

  it("keeps the snapshot reference when the state does not change", () => {
    const store = createRuntimeStateStore()
    store.setState("t1", "processing", 1)
    const before = store.getSnapshot()
    store.setState("t1", "processing", 2)
    expect(store.getSnapshot()).toBe(before)
  })

  it("notifies subscribers when state transitions", () => {
    const store = createRuntimeStateStore()
    const listener = vi.fn()
    store.subscribe(listener)
    store.setState("t1", "processing", 1)
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("does not notify when setState is a no-op", () => {
    const store = createRuntimeStateStore()
    store.setState("t1", "processing", 1)
    const listener = vi.fn()
    store.subscribe(listener)
    store.setState("t1", "processing", 9)
    expect(listener).not.toHaveBeenCalled()
  })

  it("stops notifying after unsubscribe", () => {
    const store = createRuntimeStateStore()
    const listener = vi.fn()
    const unsubscribe = store.subscribe(listener)
    unsubscribe()
    store.setState("t1", "processing", 1)
    expect(listener).not.toHaveBeenCalled()
  })

  it("removes an entry and notifies", () => {
    const store = createRuntimeStateStore()
    const listener = vi.fn()
    store.setState("t1", "processing", 1)
    store.subscribe(listener)
    store.remove("t1")
    expect(store.getSnapshot()).toEqual({})
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it("remove on an unknown id is a silent no-op", () => {
    const store = createRuntimeStateStore()
    const listener = vi.fn()
    store.subscribe(listener)
    store.remove("t-missing")
    expect(listener).not.toHaveBeenCalled()
  })
})
