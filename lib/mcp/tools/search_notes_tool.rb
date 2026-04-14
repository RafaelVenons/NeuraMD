# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SearchNotesTool < MCP::Tool
      tool_name "search_notes"
      description "Search NeuraMD notes by text query and/or property filters. Returns matching notes with title, slug, excerpt, and tags."

      input_schema(
        type: "object",
        properties: {
          query: {type: "string", description: "Text to search for in note titles and content. When regex: true, this is a POSIX regex pattern."},
          limit: {type: "integer", description: "Maximum number of results (default: 10, max: 50)"},
          regex: {type: "boolean", description: "If true, interpret query as a POSIX regex matched against title and content (case-insensitive). Defaults to false."},
          property_filters: {type: "string", description: 'JSON object of property key-value pairs to filter by. Example: \'{"status":"draft"}\'. Combine with query for text+property search, or use alone to list notes by property value.'}
        },
        required: ["query"]
      )

      def self.call(query: "", limit: 10, regex: false, property_filters: nil, server_context: nil)
        parsed_filters = parse_property_filters(property_filters)

        result = Search::NoteQueryService.call(
          scope: Note.active.includes(:note_aliases),
          query: query.to_s,
          regex: regex,
          limit: [limit.to_i, 1].max,
          property_filters: parsed_filters
        )

        if result.error.present?
          return MCP::Tool::Response.new([{type: "text", text: result.error}], error: true)
        end

        notes = result.notes.map do |note|
          {
            slug: note.slug,
            title: note.title,
            aliases: note.note_aliases.map(&:name),
            excerpt: excerpt_for(note),
            tags: note.tags.pluck(:name)
          }
        end

        json_response(notes: notes, query: query, regex: regex, has_more: result.has_more)
      end

      def self.excerpt_for(note)
        text = note.head_revision&.content_plain.to_s
        text.truncate(200)
      end

      def self.parse_property_filters(raw)
        return nil if raw.blank?
        parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      def self.json_response(data)
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end
    end
  end
end
