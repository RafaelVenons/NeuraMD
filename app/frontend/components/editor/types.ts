export type NoteTag = {
  id: number
  name: string
  color_hex: string | null
}

export type NoteSummary = {
  id: string
  slug: string
  title: string
  detected_language: string | null
  head_revision_id: string | null
}

export type NoteRevision = {
  id: string | null
  kind: string | null
  content_markdown: string
  updated_at: string | null
}

export type PropertyValueType =
  | "text"
  | "long_text"
  | "number"
  | "boolean"
  | "date"
  | "datetime"
  | "enum"
  | "multi_enum"
  | "url"
  | "note_reference"
  | "list"

export type PropertyDefinition = {
  key: string
  value_type: PropertyValueType
  label: string | null
  description: string | null
  config: Record<string, unknown> | null
}

export type NotePayload = {
  note: NoteSummary
  revision: NoteRevision
  tags: NoteTag[]
  aliases: string[]
  properties: Record<string, unknown>
  properties_errors: Record<string, unknown>
  property_definitions: PropertyDefinition[]
}
