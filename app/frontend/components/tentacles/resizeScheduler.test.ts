import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { createResizeScheduler } from "~/components/tentacles/resizeScheduler"

describe("createResizeScheduler", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it("collapses a burst of schedule calls into a single trailing onFit", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.schedule()
    scheduler.schedule()
    scheduler.schedule()
    expect(onFit).not.toHaveBeenCalled()

    vi.advanceTimersByTime(99)
    expect(onFit).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(onFit).toHaveBeenCalledTimes(1)
  })

  it("resets the timer when schedule is called again before it fires", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.schedule()
    vi.advanceTimersByTime(80)
    scheduler.schedule()
    vi.advanceTimersByTime(80)
    expect(onFit).not.toHaveBeenCalled()

    vi.advanceTimersByTime(20)
    expect(onFit).toHaveBeenCalledTimes(1)
  })

  it("flush runs onFit immediately and cancels the pending timer", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.schedule()
    scheduler.flush()
    expect(onFit).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(1000)
    expect(onFit).toHaveBeenCalledTimes(1)
  })

  it("can schedule again after flush", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.flush()
    scheduler.schedule()
    vi.advanceTimersByTime(100)
    expect(onFit).toHaveBeenCalledTimes(2)
  })

  it("dispose cancels a pending timer without firing", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.schedule()
    scheduler.dispose()
    vi.advanceTimersByTime(1000)
    expect(onFit).not.toHaveBeenCalled()
  })

  it("schedule and flush after dispose are no-ops", () => {
    const onFit = vi.fn()
    const scheduler = createResizeScheduler({ onFit, debounceMs: 100 })

    scheduler.dispose()
    scheduler.schedule()
    scheduler.flush()
    vi.advanceTimersByTime(1000)
    expect(onFit).not.toHaveBeenCalled()
  })
})
