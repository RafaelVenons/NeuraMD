# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class NoteGraphTool < MCP::Tool
      tool_name "note_graph"
      description "Get graph neighbors of a NeuraMD note. Returns outgoing and incoming links with roles."

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "The note slug to get graph neighbors for"},
          depth: {type: "integer", description: "Link traversal depth (default: 1, currently only 1 supported)"}
        },
        required: ["slug"]
      )

      def self.call(slug:, depth: 1, server_context: nil)
        note = Note.active.find_by(slug: slug)
        return error_response("Note not found: #{slug}") unless note

        links = []

        note.active_outgoing_links.includes(:dst_note).each do |link|
          links << {
            direction: "outgoing",
            source_slug: note.slug,
            target_slug: link.dst_note.slug,
            target_title: link.dst_note.title,
            role: link.hier_role
          }
        end

        note.active_incoming_links.includes(:src_note).each do |link|
          links << {
            direction: "incoming",
            source_slug: link.src_note.slug,
            target_slug: note.slug,
            target_title: link.src_note.title,
            role: link.hier_role
          }
        end

        data = {
          center: {slug: note.slug, title: note.title},
          links: links
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
