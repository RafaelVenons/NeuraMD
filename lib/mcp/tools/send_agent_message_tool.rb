# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class SendAgentMessageTool < MCP::Tool
      extend NoteFinder

      tool_name "send_agent_message"
      description "Send a short text message from one tentacle (note) to another. Persists in the inbox of the recipient until read via read_agent_inbox. Content cap: 8KB."

      input_schema(
        type: "object",
        properties: {
          from_slug: {type: "string", description: "Slug of the sender note (the tentacle producing the message)"},
          to_slug:   {type: "string", description: "Slug of the recipient note (the tentacle that should read it)"},
          content:   {type: "string", description: "Plain-text message body. Truncated to 8KB."}
        },
        required: ["from_slug", "to_slug", "content"]
      )

      def self.call(from_slug:, to_slug:, content:, server_context: nil)
        from = find_note(from_slug)
        return error_response("Sender note not found: #{from_slug}") unless from

        to = find_note(to_slug)
        return error_response("Recipient note not found: #{to_slug}") unless to

        message = AgentMessages::Sender.call(from: from, to: to, content: content)

        data = {
          sent: true,
          message_id: message.id,
          from_slug: from.slug,
          to_slug:   to.slug,
          created_at: message.created_at.iso8601,
          content_bytes: message.content.bytesize,
          truncated: message.content.include?("[truncated — original")
        }
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
