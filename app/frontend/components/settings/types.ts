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
