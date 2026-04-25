# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class MyTasksTool < MCP::Tool
      tool_name "my_tasks"
      description <<~DESC.strip
        Lista notas-iniciativa abertas atribuídas a um agente (claimed_by = agent_slug AND closed_at IS NULL). Ordem: claimed_at desc (mais recente primeiro). Sem auth — qualquer agente pode consultar a fila de qualquer outro. Default agent_slug = `ENV["NEURAMD_AGENT_SLUG"]`.
      DESC

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      input_schema(
        type: "object",
        properties: {
          agent_slug: {type: "string", description: "Slug do agente. Omitido = caller (ENV NEURAMD_AGENT_SLUG)."},
          limit: {type: "integer", description: "Máximo de tasks (default 50, max 100)"}
        }
      )

      def self.call(agent_slug: nil, limit: nil, server_context: nil)
        slug = (agent_slug || ENV["NEURAMD_AGENT_SLUG"]).to_s.strip
        return error_response("agent_slug not provided and NEURAMD_AGENT_SLUG is unset") if slug.empty?

        bounded_limit = bound_limit(limit)

        notes = Tasks::Protocol.my_tasks(agent_slug: slug, limit: bounded_limit)

        json_response(
          agent_slug: slug,
          count: notes.size,
          tasks: notes.map { |n| serialize_task(n) }
        )
      end

      def self.bound_limit(raw)
        value = raw.to_i
        return DEFAULT_LIMIT if value <= 0
        [value, MAX_LIMIT].min
      end

      def self.serialize_task(note)
        props = note.current_properties
        {
          slug: note.slug,
          title: note.title,
          claimed_at: props["claimed_at"],
          claim_authority: props["claim_authority"],
          queue_after: props["queue_after"]
        }
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
