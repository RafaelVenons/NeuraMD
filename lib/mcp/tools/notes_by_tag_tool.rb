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
          exclude_tags: {type: "string", description: "Comma-separated tag names to exclude. Notes carrying any of these tags are filtered out."},
          limit: {type: "integer", description: "Maximum number of results (default: 20)"}
        },
        required: ["tag"]
      )

      def self.call(tag:, exclude_tags: nil, limit: 20, server_context: nil)
        tag_record = Tag.find_by(name: tag)
        return error_response("Tag not found: #{tag}") unless tag_record

        scope = tag_record.notes.active.includes(:head_revision)
        scope = exclude_notes_with_tags(scope, exclude_tags)

        notes = scope
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

      def self.exclude_notes_with_tags(scope, exclude_tags)
        return scope if exclude_tags.blank?

        names = exclude_tags.to_s.split(",").map(&:strip).reject(&:blank?)
        return scope if names.empty?

        excluded_ids = NoteTag
          .joins(:tag)
          .where(tags: {name: names})
          .distinct
          .pluck(:note_id)

        return scope if excluded_ids.empty?
        scope.where.not(id: excluded_ids)
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
