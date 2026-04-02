# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ReadNoteTool < MCP::Tool
      extend NoteFinder

      tool_name "read_note"
      description "Read a NeuraMD note by slug or alias. Returns full content, tags, aliases, and links. Follows slug redirects and aliases."

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "The note slug (URL identifier)"}
        },
        required: ["slug"]
      )

      def self.call(slug:, server_context: nil)
        note = find_note(slug)
        return error_response("Note not found: #{slug}") unless note

        outgoing = note.active_outgoing_links.includes(:dst_note).map do |link|
          {
            target_slug: link.dst_note.slug,
            target_title: link.dst_note.title,
            role: link.hier_role,
            direction: "outgoing"
          }
        end

        backlinks = note.active_incoming_links.includes(:src_note).map do |link|
          {
            source_slug: link.src_note.slug,
            source_title: link.src_note.title,
            role: link.hier_role,
            direction: "incoming"
          }
        end

        data = {
          slug: note.slug,
          title: note.title,
          aliases: note.note_aliases.pluck(:name),
          body: note.head_revision&.content_markdown.to_s,
          tags: note.tags.pluck(:name),
          properties: note.current_properties,
          links: outgoing,
          backlinks: backlinks,
          created_at: note.created_at.iso8601,
          updated_at: note.updated_at.iso8601
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
