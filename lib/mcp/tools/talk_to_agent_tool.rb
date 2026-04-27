# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    # Bounded conversation primitive for the remote gateway. Sender
    # identity is locked to the token's bound agent_note (forgery-proof
    # at the protocol level). Recipient is any active note that carries
    # an `agente-*` tag — i.e. another tentacle in the team — so a
    # leaked token can't broadcast to the human or to arbitrary notes.
    # Auto-wakes the recipient's tentacle session via S2S unless
    # wake: false; wake failure is non-fatal because the message
    # persists in the inbox regardless.
    class TalkToAgentTool < MCP::Tool
      AGENT_TAG_PREFIX = "agente-"

      tool_name "talk_to_agent"
      description <<~DESC.strip
        Send a message to another agent (tentacle) by slug. Sender is
        your token's bound agent note (set with AGENT_SLUG when the
        token was issued); from_slug in arguments is ignored. Recipient
        must be an active note carrying an `agente-*` tag — passing a
        human or arbitrary note slug is rejected. Auto-wakes the
        recipient's tentacle session unless wake: false; wake failure
        is non-fatal (message persists in inbox). Returns
        sent/message_id/wake_warning.
      DESC

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug of the recipient agent's note"},
          content: {type: "string", description: "Plain-text message body. Truncated to 8KB."},
          wake: {type: "boolean", description: "Activate the recipient tentacle session after sending (default true)."}
        },
        required: ["slug", "content"]
      )

      def self.call(slug:, content:, wake: true, server_context: nil, **_ignored)
        token = server_context && server_context[:mcp_token]
        return error_response("Missing mcp_token in server_context — call only valid through the remote gateway.") unless token

        sender = token.agent_note
        return error_response("Token has no agent identity (agent_note_id). Re-issue the token with AGENT_SLUG=<note-slug> to bind it before calling this tool.") if sender.nil?

        recipient_slug = slug.to_s.strip
        return error_response("slug cannot be blank") if recipient_slug.empty?

        recipient = Note.active.includes(:tags).find_by(slug: recipient_slug)
        return error_response("Recipient note not found: #{recipient_slug}") if recipient.nil?

        unless recipient.tags.any? { |t| t.name.to_s.start_with?(AGENT_TAG_PREFIX) }
          return error_response("Recipient #{recipient_slug.inspect} is not an agent (no `#{AGENT_TAG_PREFIX}*` tag). Use spawn_child_tentacle or tag the note first.")
        end

        message = AgentMessages::Sender.call(from: sender, to: recipient, content: content)

        wake_succeeded = nil
        wake_warning = nil
        wake_session = nil
        if wake
          begin
            activate_response = ActivateTentacleSessionTool.call(
              slug: recipient_slug,
              initial_prompt: build_wake_prompt(sender_slug: sender.slug, recipient_slug: recipient_slug, content: content)
            )
            wake_succeeded, wake_warning, wake_session = inspect_activate_response(activate_response)
          rescue StandardError => e
            wake_succeeded = false
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
          wake_succeeded: wake_succeeded,
          wake_warning: wake_warning,
          wake_session: wake_session
        }.compact
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      rescue AgentMessages::Sender::InvalidRecipient, AgentMessages::Sender::EmptyContent => e
        error_response(e.message)
      end

      # `ActivateTentacleSessionTool.call` never raises — it returns an
      # MCP::Tool::Response with `error: true` for non-2xx S2S, missing
      # token, plaintext-refusal, and JSON parse errors. Returning the
      # tuple `[succeeded?, warning, session_summary]` lets the caller
      # populate wake_warning/wake_session honestly instead of relying
      # on Ruby exception flow that the activator never enters.
      def self.inspect_activate_response(response)
        response_hash = response.to_h
        text = response_hash.dig(:content, 0, :text) || response_hash.dig("content", 0, "text")

        if response_hash[:isError] || response_hash["isError"]
          [false, text.to_s.presence || "wake failed (no error text)", nil]
        else
          parsed = begin
            JSON.parse(text.to_s)
          rescue JSON::ParserError
            nil
          end
          session = nil
          if parsed.is_a?(Hash)
            session = {
              pid: parsed["pid"],
              started_at: parsed["started_at"],
              reused: parsed["reused"]
            }.compact
            session = nil if session.empty?
          end
          [true, nil, session]
        end
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end

      # Compact wake-up prompt fed to the recipient's first stdin so the
      # spawned session knows it has fresh inbox work and the doctrinal
      # "silence is a bug" rule from the Carta. Content is truncated to
      # ~240 bytes — the full message stays in the inbox for proper
      # consumption via read_agent_inbox.
      WAKE_CONTENT_SNIPPET_BYTES = 240

      def self.build_wake_prompt(sender_slug:, recipient_slug:, content:)
        snippet = content.to_s.byteslice(0, WAKE_CONTENT_SNIPPET_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub
        snippet += "…" if content.to_s.bytesize > WAKE_CONTENT_SNIPPET_BYTES
        <<~PROMPT.strip
          Mensagem nova no seu inbox vinda de #{sender_slug}: "#{snippet}"
          Rode `read_agent_inbox slug=#{recipient_slug} only_pending=true mark_delivered=true` pra ver íntegra (e outras pendentes), processe e responda via `send_agent_message` pro #{sender_slug} — regra da Carta comum: silêncio é defeito.
        PROMPT
      end
    end
  end
end
