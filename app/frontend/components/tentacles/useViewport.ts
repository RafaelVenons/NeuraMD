import { useEffect, useState } from "react"

export type Viewport = { width: number; height: number }

const FALLBACK: Viewport = { width: 1920, height: 1080 }

function readViewport(): Viewport {
  if (typeof window === "undefined") return FALLBACK
  return { width: window.innerWidth, height: window.innerHeight }
}

export function useViewport(): Viewport {
  const [viewport, setViewport] = useState<Viewport>(readViewport)

  useEffect(() => {
    if (typeof window === "undefined") return
    const handler = () => setViewport(readViewport())
    handler()
    window.addEventListener("resize", handler, { passive: true })
    return () => window.removeEventListener("resize", handler)
  }, [])

  return viewport
}
