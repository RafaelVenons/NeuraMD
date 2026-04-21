# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SpawnChildTentacleTool < MCP::Tool
      extend NoteFinder

      tool_name "spawn_child_tentacle"
      description "Create a child tentacle (note) wikilinked to a parent via [[Parent|f:uuid]]. Adds the `tentacle` tag plus any extras, seeds an empty `## Todos` section, and returns the new slug. Optional `cwd` (whitelisted) and `initial_prompt` (≤2KB) are persisted as properties for the runtime to honor on session start. Open the terminal at /notes/<slug>/tentacle."

      CWD_ALLOWED_PREFIXES = Tentacles::BootConfig::CWD_ALLOWED_PREFIXES
      INITIAL_PROMPT_MAX_BYTES = Tentacles::BootConfig::INITIAL_PROMPT_MAX_BYTES

      input_schema(
        type: "object",
        properties: {
          parent_slug:    {type: "string", description: "Slug of the parent tentacle (the note this child reports to)"},
          title:          {type: "string", description: "Title of the new child note"},
          description:    {type: "string", description: "Optional description / scope (markdown). Inserted between the parent link and the Todos heading."},
          extra_tags:     {type: "string", description: "Optional comma-separated tags. `tentacle` is always added."},
          cwd:            {type: "string", description: "Absolute path where the tentacle should operate. Must exist and be under /home/venom/projects/. Stored as property tentacle_cwd."},
          initial_prompt: {type: "string", description: "Boot message written to the session's stdin on first connect. Max 2048 bytes. Stored as property tentacle_initial_prompt."}
        },
        required: ["parent_slug", "title"]
      )

      def self.call(parent_slug:, title:, description: nil, extra_tags: nil,
                    cwd: nil, initial_prompt: nil, server_context: nil)
        parent = find_note(parent_slug)
        return error_response("Parent note not found: #{parent_slug}") unless parent

        canonical_cwd, cwd_error = Tentacles::BootConfig.canonicalize_cwd(cwd)
        return error_response(cwd_error) if cwd_error

        validated_prompt, prompt_error = Tentacles::BootConfig.validate_initial_prompt(initial_prompt)
        return error_response(prompt_error) if prompt_error

        result = Tentacles::ChildSpawner.call(
          parent: parent, title: title, description: description, extra_tags: extra_tags,
          cwd: canonical_cwd, initial_prompt: validated_prompt
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
