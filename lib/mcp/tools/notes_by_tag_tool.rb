# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class NotesByTagTool < MCP::Tool
      tool_name "notes_by_tag"
      description "List NeuraMD notes filtered by tag name. Returns slug, title, and excerpt."

      input_schema(
        type: "object",
        properties: {
          tag: {type: "string", description: "Tag name to filter by"},
          limit: {type: "integer", description: "Maximum number of results (default: 20)"}
        },
        required: ["tag"]
      )

      def self.call(tag:, limit: 20, server_context: nil)
        tag_record = Tag.find_by(name: tag)
        return error_response("Tag not found: #{tag}") unless tag_record

        notes = tag_record.notes.active
          .includes(:head_revision)
          .order(updated_at: :desc)
          .limit([limit.to_i, 1].max)
          .map do |note|
            {
              slug: note.slug,
              title: note.title,
              excerpt: note.head_revision&.content_plain.to_s.truncate(200)
            }
          end

        MCP::Tool::Response.new([{type: "text", text: {notes: notes}.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
