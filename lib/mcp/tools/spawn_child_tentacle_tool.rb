# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SpawnChildTentacleTool < MCP::Tool
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
        parent = find_note(parent_slug)
        return error_response("Parent note not found: #{parent_slug}") unless parent

        result = Tentacles::ChildSpawner.call(
          parent: parent, title: title, description: description, extra_tags: extra_tags
        )
        child = result.child

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
      rescue Tentacles::ChildSpawner::BlankTitle => e
        error_response("Title cannot be blank: #{e.message}")
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
