import type { GraphNoteTag, GraphTag } from "~/components/graph/types"

export const AGENT_ROLE_PALETTE: Record<string, string> = {
  "agente-gerente": "#fbbf24",
  "agente-agenda": "#f97316",
  "agente-cicd": "#4ade80",
  "agente-devops": "#10b981",
  "agente-gw": "#22d3ee",
  "agente-qa": "#a78bfa",
  "agente-rubi": "#ef4444",
  "agente-react": "#38bdf8",
  "agente-uxui": "#c084fc",
  "agente-especialista-neuramd": "#60a5fa",
  "agente-secinfo": "#f87171",
  "agente-redteam": "#dc2626",
  "agente-supply-chain": "#d97706",
  "agente-team-raiz": "#fb923c",
  "agente-python": "#eab308",
  "agente-telegram": "#0ea5e9",
  "agente-dev-catarata": "#06b6d4",
  "agente-dev-maple": "#84cc16",
  "agente-dev-sage": "#14b8a6",
  "agente-dev-shopai": "#ec4899",
  "agente-sage-worker": "#0891b2",
}

export const DEFAULT_AGENT_COLOR = "#b4a7d6"

export function agentColorMap(
  agentIds: Set<string>,
  tags: GraphTag[],
  noteTags: GraphNoteTag[],
  palette: Record<string, string> = AGENT_ROLE_PALETTE,
  fallback: string = DEFAULT_AGENT_COLOR
): Map<string, string> {
  if (agentIds.size === 0) return new Map()

  const tagNameById = new Map(tags.map((t) => [t.id, t.name]))
  const rolesByNote = new Map<string, string[]>()

  for (const nt of noteTags) {
    if (!agentIds.has(nt.note_id)) continue
    const name = tagNameById.get(nt.tag_id)
    if (!name) continue
    if (name === "agente-team" || name === "agente-team-template") continue
    if (!name.startsWith("agente-")) continue
    const arr = rolesByNote.get(nt.note_id) ?? []
    arr.push(name)
    rolesByNote.set(nt.note_id, arr)
  }

  const result = new Map<string, string>()
  for (const id of agentIds) {
    const roles = rolesByNote.get(id) ?? []
    const color = roles.map((r) => palette[r]).find((c) => c !== undefined) ?? fallback
    result.set(id, color)
  }
  return result
}
