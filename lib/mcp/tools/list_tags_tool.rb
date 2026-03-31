# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ListTagsTool < MCP::Tool
      tool_name "list_tags"
      description "List all tags in NeuraMD with their note counts."

      input_schema(
        type: "object",
        properties: {}
      )

      def self.call(server_context: nil)
        tags = Tag.order(:name).map do |tag|
          {
            name: tag.name,
            color: tag.color_hex,
            notes_count: tag.notes.active.count
          }
        end

        MCP::Tool::Response.new([{type: "text", text: {tags: tags}.to_json}])
      end
    end
  end
end
