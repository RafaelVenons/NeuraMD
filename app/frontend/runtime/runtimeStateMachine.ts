export type RuntimeState = "idle" | "processing" | "needs_input" | "exited"

export type RuntimeEvent =
  | { type: "input" }
  | { type: "output" }
  | { type: "silence" }
  | { type: "exit" }

export function deriveStateFromEvent(
  prev: RuntimeState | null,
  event: RuntimeEvent
): RuntimeState {
  switch (event.type) {
    case "exit":
      return "exited"
    case "input":
    case "output":
      return "processing"
    case "silence":
      if (prev === "processing") return "needs_input"
      return prev ?? "idle"
  }
}
