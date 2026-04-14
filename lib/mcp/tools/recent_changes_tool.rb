# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class RecentChangesTool < MCP::Tool
      tool_name "recent_changes"
      description "List notes most recently modified (by head revision timestamp). Returns slug, title, tags, and changed_at in ISO8601. Useful for picking up where work left off."

      input_schema(
        type: "object",
        properties: {
          limit: {type: "integer", description: "Maximum number of notes (default: 20, max: 100)"},
          since: {type: "string", description: "ISO8601 timestamp — only return notes changed after this. Optional."},
          tag: {type: "string", description: "Restrict to notes carrying this tag. Optional."}
        }
      )

      def self.call(limit: 20, since: nil, tag: nil, server_context: nil)
        bounded_limit = [[limit.to_i, 1].max, 100].min

        scope = Note.active
          .joins("INNER JOIN note_revisions head_rev ON head_rev.id = notes.head_revision_id")
          .includes(:tags)
          .select("notes.*, head_rev.created_at AS head_revision_created_at")
          .order("head_rev.created_at DESC")
          .limit(bounded_limit)

        if since.present?
          begin
            ts = Time.iso8601(since.to_s)
            scope = scope.where("head_rev.created_at > ?", ts)
          rescue ArgumentError => e
            return error_response("Invalid 'since' timestamp: #{e.message}")
          end
        end

        if tag.present?
          tag_record = Tag.find_by("lower(name) = lower(?)", tag.to_s.strip)
          return json_response(notes: []) unless tag_record
          scope = scope.joins(:tags).where(tags: {id: tag_record.id})
        end

        notes = scope.map do |note|
          {
            slug: note.slug,
            title: note.title,
            tags: note.tags.map(&:name),
            changed_at: note.head_revision_created_at.iso8601
          }
        end

        json_response(notes: notes, count: notes.length)
      end

      def self.json_response(data)
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
