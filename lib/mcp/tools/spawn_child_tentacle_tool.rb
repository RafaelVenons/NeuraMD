# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SpawnChildTentacleTool < MCP::Tool
      include ::DomainEvents
      extend NoteFinder

      tool_name "spawn_child_tentacle"
      description "Create a child tentacle (note) wikilinked to a parent via [[Parent|f:uuid]]. Adds the `tentacle` tag plus any extras, seeds an empty `## Todos` section, and returns the new slug. Open the terminal at /notes/<slug>/tentacle."

      input_schema(
        type: "object",
        properties: {
          parent_slug: {type: "string", description: "Slug of the parent tentacle (the note this child reports to)"},
          title:       {type: "string", description: "Title of the new child note"},
          description: {type: "string", description: "Optional description / scope (markdown). Inserted between the parent link and the Todos heading."},
          extra_tags:  {type: "string", description: "Optional comma-separated tags. `tentacle` is always added."}
        },
        required: ["parent_slug", "title"]
      )

      def self.call(parent_slug:, title:, description: nil, extra_tags: nil, server_context: nil)
        return error_response("Title cannot be blank") if title.to_s.strip.blank?

        parent = find_note(parent_slug)
        return error_response("Parent note not found: #{parent_slug}") unless parent

        body = compose_body(parent: parent, description: description)

        child = Note.new(title: title.strip, note_kind: "markdown")
        return error_response("Failed to create note: #{child.errors.full_messages.join(", ")}") unless child.save

        revision = child.note_revisions.create!(content_markdown: body, revision_kind: :checkpoint)
        child.update!(head_revision_id: revision.id)
        publish_event("note.created", note_id: child.id, slug: child.slug, title: child.title)

        Links::SyncService.call(src_note: child, revision: revision, content: body)
        apply_tags!(child, extra_tags)

        data = {
          spawned: true,
          slug: child.slug,
          id: child.id,
          title: child.title,
          parent_slug: parent.slug,
          parent_id: parent.id,
          tags: child.tags.pluck(:name),
          tentacle_url: "/notes/#{child.slug}/tentacle"
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.compose_body(parent:, description:)
        link_line = "[[#{parent.title}|f:#{parent.id}]]"
        desc = description.to_s.strip
        body = +link_line
        body << "\n\n" << desc unless desc.empty?
        body << "\n\n## Todos\n\n"
        body
      end

      def self.apply_tags!(note, extra_tags)
        names = ["tentacle"] + extra_tags.to_s.split(",").map(&:strip).reject(&:blank?)
        names.uniq.each do |name|
          tag = Tag.find_or_create_by!(name: name.downcase) { |t| t.tag_scope = "note" }
          note.tags << tag unless note.tags.include?(tag)
        end
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
