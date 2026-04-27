# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    # Counterpart to TalkToAgentTool: scoped read of the inbox of the
    # token's bound agent_note. The slug isn't an argument — leak across
    # tokens is impossible by construction. Snapshot only; long-poll is
    # explicitly out of scope (would tie up a Puma worker).
    class ReadMyInboxTool < MCP::Tool
      tool_name "read_my_inbox"
      description <<~DESC.strip
        List messages in the inbox of your token's bound agent note.
        Newest first. Defaults to only_pending: true so each call sees
        only what hasn't been delivered yet. mark_delivered: true flips
        them to delivered as a side effect — use it after the caller
        has actually consumed the messages.
      DESC

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 200

      input_schema(
        type: "object",
        properties: {
          only_pending: {type: "boolean", description: "Restrict to undelivered messages (default true)"},
          mark_delivered: {type: "boolean", description: "After reading, mark all currently-pending messages as delivered (default false)"},
          limit: {type: "integer", description: "Max messages to return (1..#{MAX_LIMIT}, default #{DEFAULT_LIMIT})"}
        }
      )

      def self.call(only_pending: true, mark_delivered: false, limit: DEFAULT_LIMIT, server_context: nil, **_ignored)
        token = server_context && server_context[:mcp_token]
        return error_response("Missing mcp_token in server_context — call only valid through the remote gateway.") unless token

        note = token.agent_note
        return error_response("Token has no agent identity (agent_note_id). Re-issue the token with AGENT_SLUG=<note-slug> to bind it before calling this tool.") if note.nil?

        effective_limit = limit.to_i.clamp(1, MAX_LIMIT)
        messages = AgentMessages::Inbox.for(note, limit: effective_limit, only_pending: only_pending).to_a

        flipped = 0
        if mark_delivered
          pending_ids = messages.reject(&:delivered?).map(&:id)
          flipped = AgentMessages::Inbox.mark_delivered!(note, ids: pending_ids)
          messages.each { |m| m.delivered_at ||= Time.current if pending_ids.include?(m.id) }
        end

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
