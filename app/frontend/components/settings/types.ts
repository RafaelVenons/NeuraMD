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

export type PropertyDefinitionDto = {
  id: string
  key: string
  value_type: PropertyValueType
  label: string | null
  description: string | null
  config: Record<string, unknown>
  system: boolean
  archived: boolean
  position: number
}

export type PropertyDefinitionsResponse = {
  definitions: PropertyDefinitionDto[]
}

export type PropertyDefinitionResponse = {
  definition: PropertyDefinitionDto
}

export type FileImportDto = {
  id: string
  original_filename: string
  status: string
  base_tag: string
  import_tag: string
  notes_created: number | null
  error_message: string | null
  created_at: string
  completed_at: string | null
}

export type FileImportsResponse = {
  imports: FileImportDto[]
}

export type AiRequestDto = {
  id: string
  capability: string
  provider: string
  status: string
  attempts_count: number
  max_attempts: number
  queue_position: number
  last_error_kind: string | null
  error_message: string | null
  created_at: string
  note: { slug: string; title: string } | null
}

export type AiRequestsResponse = {
  requests: AiRequestDto[]
}

export type TagAdminDto = {
  id: string
  name: string
  color_hex: string | null
  tag_scope: string
  notes_count: number
}

export type TagAdminResponse = {
  tags: TagAdminDto[]
}
