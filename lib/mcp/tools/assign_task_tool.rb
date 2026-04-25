# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class AssignTaskTool < MCP::Tool
      extend NoteFinder

      tool_name "assign_task"
      description <<~DESC.strip
        Atribui uma nota-iniciativa a um agente. Camada 1 do protocolo Tasks em voo: registra `claimed_by`, `claimed_at`, `claim_authority` (quem chamou) e opcionalmente `queue_after`. Auth: só `gerente` (ou agente-pai operacional explicitamente delegado, ex: `devops` → `sentinela-de-deploy`) pode atribuir. Caller derivado de `ENV["NEURAMD_AGENT_SLUG"]`. Retorna 403-equivalente se não autorizado.
      DESC

      input_schema(
        type: "object",
        properties: {
          note_slug: {type: "string", description: "Slug da nota-iniciativa a ser atribuída"},
          agent_slug: {type: "string", description: "Slug do agente que vai executar"},
          queue_after: {type: "string", description: "(opcional) slug de outra nota que esta deve esperar terminar"}
        },
        required: ["note_slug", "agent_slug"]
      )

      def self.call(note_slug:, agent_slug:, queue_after: nil, server_context: nil)
        caller_slug = ENV["NEURAMD_AGENT_SLUG"].to_s.strip
        return error_response("caller identity unknown — NEURAMD_AGENT_SLUG not set in this MCP process. Re-spawn the tentacle via SessionControl/CronTickJob to ground identity.") if caller_slug.empty?

        note = find_note(note_slug)
        return error_response("note not found: #{note_slug}") unless note

        result = Tasks::Protocol.assign(
          note: note,
          agent_slug: agent_slug,
          claim_authority: caller_slug,
          queue_after: queue_after
        )

        json_response(
          assigned: true,
          note_slug: result.slug,
          claimed_by: agent_slug,
          claim_authority: caller_slug,
          claimed_at: result.current_properties["claimed_at"],
          queue_after: result.current_properties["queue_after"]
        )
      rescue Tasks::Protocol::Unauthorized => e
        error_response("403: #{e.message}")
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
