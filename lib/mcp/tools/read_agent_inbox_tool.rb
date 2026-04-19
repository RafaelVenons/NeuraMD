# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ReadAgentInboxTool < MCP::Tool
      extend NoteFinder

      tool_name "read_agent_inbox"
      description "Read the inbox of a tentacle (note). Newest first. Optionally filter to pending and/or flip them to delivered as a side effect — use mark_delivered: true after the agent has actually consumed the messages."

      input_schema(
        type: "object",
        properties: {
          slug:            {type: "string",  description: "Slug of the recipient note whose inbox to read"},
          limit:           {type: "integer", description: "Max messages to return (1..200, default 50)"},
          only_pending:    {type: "boolean", description: "Restrict to undelivered messages (default false)"},
          mark_delivered:  {type: "boolean", description: "After reading, mark all currently-pending messages as delivered (default false)"}
        },
        required: ["slug"]
      )

      def self.call(slug:, limit: nil, only_pending: false, mark_delivered: false, server_context: nil)
        note = find_note(slug)
        return error_response("Recipient note not found: #{slug}") unless note

        effective_limit = limit.nil? ? AgentMessages::Inbox::DEFAULT_LIMIT : limit
        messages = AgentMessages::Inbox.for(note, limit: effective_limit, only_pending: only_pending).to_a

        flipped = mark_delivered ? AgentMessages::Inbox.mark_all_delivered!(note) : 0

        data = {
          slug: note.slug,
          count: messages.size,
          marked_delivered: flipped,
          messages: messages.map { |m| serialize(m) }
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.serialize(message)
        {
          id: message.id,
          from_slug: message.from_note.slug,
          from_title: message.from_note.title,
          content: message.content,
          delivered: message.delivered?,
          delivered_at: message.delivered_at&.iso8601,
          created_at: message.created_at.iso8601
        }
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
