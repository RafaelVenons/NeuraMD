export type NodeType = "root" | "structure" | "leaf" | "tentacle"

export type GraphNote = {
  id: string
  slug: string
  title: string
  excerpt?: string | null
  node_type: NodeType
  incoming_link_count: number
  outgoing_link_count: number
  has_links: boolean
  promise_count: number
  promise_titles: string[]
  has_promises: boolean
  updated_at?: string | null
  created_at?: string | null
  properties?: Record<string, unknown>
}

export type GraphLink = {
  id: string
  src_note_id: string
  dst_note_id: string
  hier_role?: string | null
}

export type GraphTag = {
  id: string
  name: string
  color_hex?: string | null
}

export type GraphNoteTag = {
  note_id: string
  tag_id: string
}

export type GraphLinkTag = {
  note_link_id: string
  tag_id: string
}

export type GraphMeta = {
  note_count: number
  link_count: number
  tag_count: number
  generated_at?: string
}

export type GraphDataset = {
  notes: GraphNote[]
  links: GraphLink[]
  tags: GraphTag[]
  noteTags: GraphNoteTag[]
  linkTags: GraphLinkTag[]
  meta: GraphMeta
}

export type GraphNode = {
  id: string
  label: string
  type: NodeType
  x: number
  y: number
  vx?: number
  vy?: number
  pinned?: boolean
  note: GraphNote
}

export type GraphEdge = {
  id: string
  source: string
  target: string
  role?: string | null
}
