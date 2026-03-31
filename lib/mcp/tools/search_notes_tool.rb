# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SearchNotesTool < MCP::Tool
      tool_name "search_notes"
      description "Search NeuraMD notes by text query. Returns matching notes with title, slug, excerpt, and tags."

      input_schema(
        type: "object",
        properties: {
          query: {type: "string", description: "Text to search for in note titles and content"},
          limit: {type: "integer", description: "Maximum number of results (default: 10, max: 50)"}
        },
        required: ["query"]
      )

      def self.call(query:, limit: 10, server_context: nil)
        result = Search::NoteQueryService.call(
          scope: Note.active,
          query: query,
          limit: [limit.to_i, 1].max
        )

        notes = result.notes.map do |note|
          {
            slug: note.slug,
            title: note.title,
            excerpt: excerpt_for(note),
            tags: note.tags.pluck(:name)
          }
        end

        json_response(notes: notes, query: query, has_more: result.has_more)
      end

      def self.excerpt_for(note)
        text = note.head_revision&.content_plain.to_s
        text.truncate(200)
      end

      def self.json_response(data)
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end
    end
  end
end
