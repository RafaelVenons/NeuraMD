# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    # One-shot status query for a given agent note: live tentacle
    # sessions, last heartbeat, inbox/outbox activity, tags. Replaces
    # the multi-step "search note + check sessions + count inbox + find
    # last outbox" dance the Gerente runs to take stock of its team.
    class AgentStatusTool < MCP::Tool
      tool_name "agent_status"
      description <<~DESC.strip
        Status snapshot for a single agent note: alive_sessions count,
        last_seen_at (most recent session heartbeat), last_started_at,
        inbox_pending_count, last_inbox_at, last_outbox_at, and tags.
        Resolves by slug; errors clearly when the slug doesn't match an
        active note. Read-only, no side effects.
      DESC

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug of the agent note to inspect"}
        },
        required: ["slug"]
      )

      def self.call(slug:, server_context: nil, **_)
        normalized = slug.to_s.strip
        return error_response("slug cannot be blank") if normalized.empty?

        note = Note.active.includes(:tags).find_by(slug: normalized)
        return error_response("Agent note not found: #{normalized}") if note.nil?

        sessions = TentacleSession.for_note(note.id)
        alive = sessions.alive
        latest_alive = alive.order(last_seen_at: :desc).first
        latest_started = sessions.order(started_at: :desc).first

        inbox = AgentMessage.inbox(note)
        outbox = AgentMessage.outbox(note)
        last_inbox = inbox.first
        last_outbox = outbox.first

        payload = {
          slug: note.slug,
          title: note.title,
          tags: note.tags.map(&:name),
          alive_sessions: alive.count,
          last_seen_at: latest_alive&.last_seen_at&.iso8601,
          last_started_at: latest_started&.started_at&.iso8601,
          inbox_pending_count: inbox.where(delivered_at: nil).count,
          inbox_total: inbox.count,
          last_inbox_at: last_inbox&.created_at&.iso8601,
          last_outbox_at: last_outbox&.created_at&.iso8601
        }
        MCP::Tool::Response.new([{type: "text", text: payload.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
