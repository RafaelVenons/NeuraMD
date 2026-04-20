import { useEffect } from "react"

export function useCommandHotkey(handler: () => void): void {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const metaKey = event.metaKey || event.ctrlKey
      if (metaKey && event.key.toLowerCase() === "k") {
        event.preventDefault()
        handler()
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [handler])
}
