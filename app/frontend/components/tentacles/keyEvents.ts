export type KeyInput = {
  key: string
  shiftKey: boolean
  ctrlKey: boolean
  altKey: boolean
  metaKey: boolean
}

export function keyEventToInputBytes(e: KeyInput): string | null {
  if (
    e.key === "Enter" &&
    e.shiftKey &&
    !e.ctrlKey &&
    !e.altKey &&
    !e.metaKey
  ) {
    return "\x1b\r"
  }
  return null
}
