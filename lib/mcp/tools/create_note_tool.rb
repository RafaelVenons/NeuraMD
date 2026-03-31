# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class CreateNoteTool < MCP::Tool
      tool_name "create_note"
      description "Create a new note in NeuraMD with title, markdown content, and optional tags."

      input_schema(
        type: "object",
        properties: {
          title: {type: "string", description: "Note title"},
          content_markdown: {type: "string", description: "Markdown content for the note"},
          tags: {type: "string", description: "Comma-separated tag names (created if they don't exist)"}
        },
        required: ["title", "content_markdown"]
      )

      def self.call(title:, content_markdown:, tags: nil, server_context: nil)
        return error_response("Title cannot be blank") if title.to_s.strip.blank?
        return error_response("Content cannot be blank") if content_markdown.to_s.strip.blank?

        note = Note.new(title: title.strip, note_kind: "markdown")
        unless note.save
          return error_response("Failed to create note: #{note.errors.full_messages.join(", ")}")
        end

        revision = note.note_revisions.create!(
          content_markdown: content_markdown,
          revision_kind: :checkpoint
        )
        note.update!(head_revision_id: revision.id)

        Links::SyncService.call(src_note: note, revision: revision, content: content_markdown)

        apply_tags!(note, tags) if tags.present?

        data = {
          created: true,
          slug: note.slug,
          title: note.title,
          id: note.id,
          tags: note.tags.pluck(:name)
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.apply_tags!(note, tags_string)
        tag_names = tags_string.to_s.split(",").map(&:strip).reject(&:blank?)
        tag_names.each do |name|
          tag = Tag.find_or_create_by!(name: name.downcase) do |t|
            t.tag_scope = "note"
          end
          note.tags << tag unless note.tags.include?(tag)
        end
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
