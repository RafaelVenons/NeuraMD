# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class RouteHumanToTool < MCP::Tool
      extend NoteFinder

      SUGGESTED_PROMPT_MAX_BYTES = 2048

      tool_name "route_human_to"
      description "Forward the human (not the task) from the current agent tentacle to another agent's tentacle, with an editable suggested prompt. Broadcasts a route-suggestion card on the caller's tentacle stream; the human clicks to open a fresh session with the target agent. The calling agent must be running inside a tentacle-scoped MCP server (server_context carries tentacle_id)."

      input_schema(
        type: "object",
        properties: {
          target_slug:      {type: "string", description: "Slug (or alias) of the target agent note the human should be routed to."},
          suggested_prompt: {type: "string", description: "Prompt to pre-fill in the target tentacle. Editable by the human before sending. Max 2048 bytes."},
          rationale:        {type: "string", description: "Optional short sentence explaining why this agent is the right destination. Rendered in the routing card."}
        },
        required: ["target_slug", "suggested_prompt"]
      )

      def self.call(target_slug:, suggested_prompt:, rationale: nil, server_context: nil)
        source = server_context && server_context[:tentacle_id].to_s
        return error_response("server_context missing tentacle_id — route_human_to must be called from a tentacle-scoped MCP server.") if source.nil? || source.empty?

        target = find_note(target_slug)
        return error_response("Target note not found: #{target_slug}") unless target

        prompt = suggested_prompt.to_s
        return error_response("suggested_prompt cannot be blank") if prompt.strip.empty?
        return error_response("suggested_prompt exceeds #{SUGGESTED_PROMPT_MAX_BYTES} bytes") if prompt.bytesize > SUGGESTED_PROMPT_MAX_BYTES

        TentacleChannel.broadcast_route_suggestion(
          tentacle_id: source,
          target_slug: target.slug,
          target_title: target.title,
          suggested_prompt: prompt,
          rationale: rationale
        )

        data = {
          routed: true,
          target_slug: target.slug,
          target_title: target.title
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
