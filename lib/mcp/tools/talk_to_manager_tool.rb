# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    # High-level wrapper around AgentMessages::Sender for the remote MCP
    # gateway. Identity comes from the McpAccessToken (its bound
    # agent_note), the recipient is hardcoded to the "gerente" note, so
    # an external client can talk to the orchestrator without being
    # handed `from_slug`/`to_slug` knobs that would let it spoof or
    # broadcast.
    class TalkToManagerTool < MCP::Tool
      MANAGER_SLUG = "gerente"

      tool_name "talk_to_manager"
      description <<~DESC.strip
        Send a message to the NeuraMD orchestrator (the "gerente" note).
        The sender is your token's bound agent note (set via AGENT_SLUG
        when the token was issued); attempts to override from_slug /
        to_slug in arguments are ignored. By default the gerente's
        tentacle session is woken up via S2S — pass wake: false to skip
        that side effect (the message persists in the inbox either
        way). Returns sent/message_id/wake_warning.
      DESC

      input_schema(
        type: "object",
        properties: {
          content: {type: "string", description: "Plain-text message body. Truncated to 8KB."},
          wake: {type: "boolean", description: "Activate the gerente tentacle session after sending (default true)."}
        },
        required: ["content"]
      )

      def self.call(content:, wake: true, server_context: nil, **_ignored)
        token = server_context && server_context[:mcp_token]
        return error_response("Missing mcp_token in server_context — call only valid through the remote gateway.") unless token

        sender = token.agent_note
        return error_response("Token has no agent identity (agent_note_id). Re-issue the token with AGENT_SLUG=<note-slug> to bind it before calling this tool.") if sender.nil?

        recipient = Note.active.find_by(slug: MANAGER_SLUG)
        return error_response("Manager note not found (slug=#{MANAGER_SLUG.inspect}).") if recipient.nil?

        message = AgentMessages::Sender.call(from: sender, to: recipient, content: content)

        wake_warning = nil
        if wake
          begin
            ActivateTentacleSessionTool.call(slug: MANAGER_SLUG)
          rescue StandardError => e
            wake_warning = "#{e.class}: #{e.message}"
          end
        end

        data = {
          sent: true,
          message_id: message.id,
          from_slug: sender.slug,
          to_slug: recipient.slug,
          created_at: message.created_at.iso8601,
          wake_attempted: wake,
          wake_warning: wake_warning
        }.compact
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      rescue AgentMessages::Sender::InvalidRecipient, AgentMessages::Sender::EmptyContent => e
        error_response(e.message)
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
