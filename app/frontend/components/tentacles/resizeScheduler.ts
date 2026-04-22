export type ResizeScheduler = {
  schedule: () => void
  flush: () => void
  dispose: () => void
}

export function createResizeScheduler(options: {
  onFit: () => void
  debounceMs: number
}): ResizeScheduler {
  let timer: ReturnType<typeof setTimeout> | null = null
  let disposed = false

  const cancel = () => {
    if (timer !== null) {
      clearTimeout(timer)
      timer = null
    }
  }

  return {
    schedule() {
      if (disposed) return
      cancel()
      timer = setTimeout(() => {
        timer = null
        options.onFit()
      }, options.debounceMs)
    },
    flush() {
      if (disposed) return
      cancel()
      options.onFit()
    },
    dispose() {
      disposed = true
      cancel()
    },
  }
}
