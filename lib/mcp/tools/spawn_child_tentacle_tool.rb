# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SpawnChildTentacleTool < MCP::Tool
      extend NoteFinder

      tool_name "spawn_child_tentacle"
      description <<~DESC.strip
        Create a child tentacle (note) wikilinked to a parent via [[Parent|f:uuid]]. Adds the `tentacle` tag plus any extras, seeds an empty `## Todos` section, and returns the new slug.

        Runtime destination (choose one, persisted as properties honored on session start):
        - `tentacle_workspace`: name of a shared workspace under NEURAMD_TENTACLE_WORKSPACE_ROOT (default /home/rafael/workspaces/). The child runs in `<workspace_root>/.tentacle-worktrees/<workspace>/<child_uuid>/` on branch `tentacle/<uuid>` of the shared repo. Use this when the child should edit a codebase collaboratively — multiple children on the same workspace get distinct branches.
        - `cwd`: absolute path whitelisted by Tentacles::BootConfig.allowed_cwd_prefixes. The child runs in `<cwd>/tmp/tentacles/<child_uuid>/` on branch `tentacle/<uuid>` of that repo. Use this for single-agent ephemeral work in a specific repo.
        - Neither set: child falls back to Rails.root (the app runtime). Avoid — runtime directory is owned by autodeploy.

        `initial_prompt` (≤2KB) is written to the session's stdin on first connect.

        Open the terminal at /notes/<slug>/tentacle.
      DESC

      INITIAL_PROMPT_MAX_BYTES = Tentacles::BootConfig::INITIAL_PROMPT_MAX_BYTES

      def self.cwd_allowed_prefixes
        Tentacles::BootConfig.allowed_cwd_prefixes
      end

      input_schema(
        type: "object",
        properties: {
          parent_slug:       {type: "string", description: "Slug of the parent tentacle (the note this child reports to)"},
          title:             {type: "string", description: "Title of the new child note"},
          description:       {type: "string", description: "Optional description / scope (markdown). Inserted between the parent link and the Todos heading."},
          extra_tags:        {type: "string", description: "Optional comma-separated tags. `tentacle` is always added."},
          tentacle_workspace: {type: "string", description: "Name of a shared workspace under NEURAMD_TENTACLE_WORKSPACE_ROOT (default /home/rafael/workspaces/). Must exist as a git repo. Stored as property tentacle_workspace. Preferred over cwd for code-editing children."},
          cwd:               {type: "string", description: "Absolute path where the tentacle should operate. Must exist and be whitelisted by Tentacles::BootConfig.allowed_cwd_prefixes. Stored as property tentacle_cwd. Ignored when tentacle_workspace is set."},
          initial_prompt:    {type: "string", description: "Boot message written to the session's stdin on first connect. Max 2048 bytes. Stored as property tentacle_initial_prompt."}
        },
        required: ["parent_slug", "title"]
      )

      def self.call(parent_slug:, title:, description: nil, extra_tags: nil,
                    cwd: nil, initial_prompt: nil, tentacle_workspace: nil, server_context: nil)
        parent = find_note(parent_slug)
        return error_response("Parent note not found: #{parent_slug}") unless parent

        workspace_given = tentacle_workspace.present? && !tentacle_workspace.to_s.strip.empty?
        cwd_given = cwd.present? && !cwd.to_s.strip.empty?
        if workspace_given && cwd_given
          return error_response(
            "cannot set both tentacle_workspace and cwd — pick one. " \
            "Workspace is preferred for code-editing children; cwd is for single-agent ephemeral work in a specific repo."
          )
        end

        validated_workspace, workspace_error = validate_workspace(tentacle_workspace)
        return error_response(workspace_error) if workspace_error

        canonical_cwd, cwd_error = Tentacles::BootConfig.canonicalize_cwd(cwd)
        return error_response(cwd_error) if cwd_error

        validated_prompt, prompt_error = Tentacles::BootConfig.validate_initial_prompt(initial_prompt)
        return error_response(prompt_error) if prompt_error

        result = Tentacles::ChildSpawner.call(
          parent: parent, title: title, description: description, extra_tags: extra_tags,
          cwd: canonical_cwd, initial_prompt: validated_prompt, workspace: validated_workspace
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

      # Returns [validated_name, nil] or [nil, error_message]. Blank input is
      # treated as "not provided" (returns [nil, nil]); names are resolved
      # against the workspace root so typos fail fast instead of surfacing
      # as EROFS at session boot.
      def self.validate_workspace(name)
        return [nil, nil] if name.nil? || name.to_s.strip.empty?

        _canonical, error = Tentacles::Workspace.resolve(name)
        return [nil, error] if error

        [name.to_s, nil]
      end
    end
  end
end
