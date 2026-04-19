# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class BulkRemoveTagTool < MCP::Tool
      tool_name "bulk_remove_tag"
      description "Remove a tag from all notes that carry it in a single call. Optionally destroy the Tag row itself afterwards. Does not create note revisions — tag membership is not versioned."

      input_schema(
        type: "object",
        properties: {
          tag: {type: "string", description: "Tag name to remove from every note that has it"},
          delete_tag: {type: "boolean", description: "If true, also destroy the Tag row after detaching (default: false)"}
        },
        required: ["tag"]
      )

      def self.call(tag:, delete_tag: false, server_context: nil)
        tag_record = Tag.find_by(name: tag)
        return error_response("Tag not found: #{tag}") unless tag_record

        removed = NoteTag.where(tag_id: tag_record.id).delete_all

        tag_deleted = false
        if delete_tag
          tag_record.destroy!
          tag_deleted = true
        end

        data = {
          tag: tag,
          removed_from: removed,
          tag_deleted: tag_deleted
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
