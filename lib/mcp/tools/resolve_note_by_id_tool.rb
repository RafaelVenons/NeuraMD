# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ResolveNoteByIdTool < MCP::Tool
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      tool_name "resolve_note_by_id"
      description "Resolve a NeuraMD note UUID to its current slug, title, and tags. Useful when you have a UUID (e.g. from a wikilink or tentacle character_key) and need human-readable identifiers."

      input_schema(
        type: "object",
        properties: {
          id: {type: "string", description: "UUID of the note to resolve"}
        },
        required: ["id"]
      )

      def self.call(id:, server_context: nil)
        unless UUID_PATTERN.match?(id.to_s)
          return error_response("Invalid UUID format: #{id}")
        end

        note = Note.active.find_by(id: id)
        return error_response("Note not found: #{id}") unless note

        data = {
          id: note.id,
          slug: note.slug,
          title: note.title,
          tags: note.tags.pluck(:name)
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
