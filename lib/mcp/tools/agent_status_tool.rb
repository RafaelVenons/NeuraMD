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

        # Two source of truths intentionally combined:
        #   1. TentacleRuntime::SESSIONS — in-memory map populated by every
        #      spawn (PTY and dtach). Authoritative for "is alive RIGHT NOW"
        #      in the current Puma worker. Required because PTY-mode spawns
        #      do not write to TentacleSession at all (only spawn_via_dtach
        #      calls persist_tentacle_session_record!), so a production
        #      deploy without NEURAMD_FEATURE_DTACH leaves the DB blind to
        #      every live agent.
        #   2. TentacleSession — DB-backed history. Survives Puma restart
        #      via bootstrap_sessions! reattach (dtach mode) and carries
        #      last_seen_at heartbeats. The runtime overrides it whenever
        #      both have an entry — runtime knows current process state,
        #      DB only knows what was last written.
        runtime_session = ::TentacleRuntime.get(note.id)
        runtime_alive = runtime_session && runtime_session.alive?

        db_sessions = TentacleSession.for_note(note.id)
        db_alive_count = db_sessions.alive.count
        db_latest_alive = db_sessions.alive.order(last_seen_at: :desc).first
        db_latest_started = db_sessions.order(started_at: :desc).first

        alive_sessions = runtime_alive ? 1 : db_alive_count
        last_started_at =
          (runtime_alive ? runtime_session.started_at : nil) ||
          db_latest_started&.started_at
        # In PTY mode there is no heartbeat tracker, so when the runtime
        # session is alive we report Time.current — we just observed it
        # alive, that's the most truthful "last seen" we can offer.
        last_seen_at =
          (runtime_alive ? Time.current : nil) ||
          db_latest_alive&.last_seen_at

        inbox = AgentMessage.inbox(note)
        outbox = AgentMessage.outbox(note)
        last_inbox = inbox.first
        last_outbox = outbox.first

        payload = {
          slug: note.slug,
          title: note.title,
          tags: note.tags.map(&:name),
          alive_sessions: alive_sessions,
          last_seen_at: last_seen_at&.iso8601,
          last_started_at: last_started_at&.iso8601,
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
