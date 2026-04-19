# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class MergeNotesTool < MCP::Tool
      extend NoteFinder

      tool_name "merge_notes"
      description "Merge source note into target. Source content appended, incoming links retargeted, slug redirect created, source soft-deleted."

      input_schema(
        type: "object",
        properties: {
          source_slug: {type: "string", description: "Slug of the note to merge FROM (will be soft-deleted)"},
          target_slug: {type: "string", description: "Slug of the note to merge INTO (receives content)"}
        },
        required: ["source_slug", "target_slug"]
      )

      def self.call(source_slug:, target_slug:, server_context: nil)
        source = find_note(source_slug)
        return error_response("Source note not found: #{source_slug}") unless source
        target = find_note(target_slug)
        return error_response("Target note not found: #{target_slug}") unless target

        result = Notes::MergeService.call(source: source, target: target, author: nil)

        data = {
          merged: true,
          source_slug: source.slug,
          source_title: source.title,
          target_slug: target.reload.slug,
          target_title: target.title,
          revision_id: result.revision.id
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      rescue ArgumentError => e
        error_response(e.message)
      rescue ActiveRecord::RecordInvalid => e
        messages = e.record&.errors&.full_messages
        detail = messages.presence&.join("; ") || e.message
        error_response("Merge failed: #{detail}")
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
