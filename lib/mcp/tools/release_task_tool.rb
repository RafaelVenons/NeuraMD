# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ReleaseTaskTool < MCP::Tool
      extend NoteFinder

      tool_name "release_task"
      description <<~DESC.strip
        Libera uma nota-iniciativa atribuída ao caller. Auth: só o próprio `claimed_by` pode liberar (caller via `ENV["NEURAMD_AGENT_SLUG"]`). Status `completed` / `abandoned` fecha a task com `closed_at` + `closed_status`. Status `handed_off` exige `handoff_to` e re-claimea pra esse slug, deixando-a aberta sob nova autoridade (caller = claim_authority do handoff).
      DESC

      input_schema(
        type: "object",
        properties: {
          note_slug: {type: "string", description: "Slug da nota a liberar"},
          status: {type: "string", description: "completed | abandoned | handed_off", enum: Tasks::Protocol::CLOSED_STATUSES},
          handoff_to: {type: "string", description: "(obrigatório se status=handed_off) slug do novo claimed_by"}
        },
        required: ["note_slug", "status"]
      )

      def self.call(note_slug:, status:, handoff_to: nil, server_context: nil)
        caller_slug = ENV["NEURAMD_AGENT_SLUG"].to_s.strip
        return error_response("caller identity unknown — NEURAMD_AGENT_SLUG not set in this MCP process") if caller_slug.empty?

        note = find_note(note_slug)
        return error_response("note not found: #{note_slug}") unless note

        result = Tasks::Protocol.release(
          note: note,
          status: status,
          caller_slug: caller_slug,
          handoff_to: handoff_to
        )

        props = result.current_properties
        json_response(
          released: true,
          note_slug: result.slug,
          status: status,
          closed_at: props["closed_at"],
          closed_status: props["closed_status"],
          claimed_by: props["claimed_by"],
          claim_authority: props["claim_authority"]
        )
      rescue Tasks::Protocol::Unauthorized => e
        error_response("403: #{e.message}")
      rescue Tasks::Protocol::InvalidStatus, Tasks::Protocol::NotClaimed => e
        error_response(e.message)
      rescue Properties::SetService::ValidationError, Properties::SetService::UnknownKeyError => e
        error_response(e.message)
      end

      def self.json_response(data)
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
