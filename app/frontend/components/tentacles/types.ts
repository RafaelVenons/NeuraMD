export type TentacleSession = {
  tentacle_id: string
  slug?: string
  title?: string
  alive: boolean
  pid: number | null
  started_at: string | null
  command: string[] | null
}

export type TentacleSessionsIndex = {
  sessions: TentacleSession[]
}

export type TentacleCableMessage =
  | { type: "output"; data: string }
  | { type: "exit"; status: number | null }
  | {
      type: "context-warning"
      ratio: number
      estimated_tokens: number
    }
  | {
      type: "route-suggestion"
      target: { slug: string; title: string }
      suggested_prompt: string
      rationale: string | null
    }

export type RouteSuggestion = {
  id: string
  target: { slug: string; title: string }
  suggested_prompt: string
  rationale: string | null
}

export type InboxMessage = {
  id: string
  from_slug: string
  from_title: string
  content: string
  delivered: boolean
  delivered_at: string | null
  created_at: string
}

export type InboxResponse = {
  slug: string
  count: number
  pending_count: number
  messages: InboxMessage[]
}

export type SpawnChildResponse = {
  spawned: boolean
  id: string
  slug: string
  title: string
  parent_slug: string
  tags: string[]
  tentacle_url: string
}

export type NoteLinkRef = {
  id: string
  slug: string
  title: string
  hier_role: string | null
}

export type NoteLinksResponse = {
  outgoing: NoteLinkRef[]
  incoming: NoteLinkRef[]
}
