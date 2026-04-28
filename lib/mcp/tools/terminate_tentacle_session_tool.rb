# frozen_string_literal: true

require "mcp"
require "net/http"
require "uri"
require "json"

module Mcp
  module Tools
    # Symmetric counterpart to ActivateTentacleSessionTool — kills a
    # tentacle session running in the neuramd-web process so callers
    # (BigBoss, Gerente, supervisor scripts) can recover deadlocked
    # agents or reapply spawn-affecting properties without SSH access
    # to the host. Authenticates with the same shared S2S token as
    # activate; the controller-side tag gate (note must carry an
    # `agente-*` tag) still applies.
    #
    # Architectural note: like activate, this tool runs inside the MCP
    # process and reaches the web worker via HTTP. Calling
    # `TentacleRuntime.stop` directly from here would no-op against the
    # MCP-process map and leave the actual web-process session alive.
    class TerminateTentacleSessionTool < MCP::Tool
      tool_name "terminate_tentacle_session"
      description <<~DESC.strip
        Terminate a tentacle session for another agent's note. Stops the in-memory session inside the running neuramd-web process and clears it from the runtime map, so the next `activate_tentacle_session` (or wake via `talk_to_agent`) spawns a fresh process picking up updated properties.

        Idempotent — when no session exists the response is `{terminated: false, reason: "no_session"}` with HTTP 200. When a session was running, the response includes `pid`, `escalated_to_kill` (true when SIGKILL was reached), and `ended_at`.

        `force: true` collapses the SIGTERM grace to zero so SIGKILL is sent immediately. Use when a session is known stuck (TUI deadlocked on a permission prompt, child ignoring TERM). Default `force: false` allows the child a brief graceful window.

        Target note must carry an `agente-*` tag (enforced server-side). Surfaces controller errors (401/403/404) as MCP errors with the original message.
      DESC

      DEFAULT_BASE_URL = "http://127.0.0.1:3000"
      TOKEN_HEADER = "X-NeuraMD-Agent-Token"

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug of the recipient agent's note (its tentacle to terminate)"},
          force: {type: "boolean", description: "When true, skip the SIGTERM grace window and go straight to SIGKILL. Default false."}
        },
        required: ["slug"]
      )

      def self.call(slug:, force: false, server_context: nil)
        return error_response("slug cannot be blank") if slug.to_s.strip.empty?

        token = resolve_token
        if token.blank?
          return error_response("S2S token not configured. Set ENV[\"AGENT_S2S_TOKEN\"] in the neuramd-web unit (systemd drop-in) or populate Rails.application.credentials.agent_s2s_token before retrying.")
        end

        uri = URI.parse("#{base_url}/api/s2s/tentacles/#{URI.encode_www_form_component(slug)}")
        return error_response("refusing to send S2S token over plaintext HTTP to non-local host #{uri.host}; use https:// or a loopback address") unless safe_transport?(uri)

        payload = {force: force ? true : false}

        body, status = delete_json(uri, payload, token.to_s)
        parsed = safe_parse(body)

        if status.between?(200, 299)
          MCP::Tool::Response.new([{type: "text", text: parsed.to_json}])
        else
          message = parsed.is_a?(Hash) && parsed["error"].present? ? parsed["error"] : body.to_s
          error_response("terminate failed (HTTP #{status}): #{message}")
        end
      rescue StandardError => e
        error_response("terminate call raised #{e.class}: #{e.message}")
      end

      def self.base_url
        ENV.fetch("NEURAMD_S2S_URL", DEFAULT_BASE_URL)
      end

      # ENV wins over Rails.application.credentials for the same
      # reason as activate's resolver: autodeploy's `git reset --hard`
      # would wipe an uncommitted credentials.yml.enc update, so the
      # production path is systemd drop-in env injection.
      def self.resolve_token
        env_value = ENV["AGENT_S2S_TOKEN"].to_s.strip
        return env_value unless env_value.empty?

        ::Rails.application.credentials.agent_s2s_token
      end

      LOOPBACK_HOSTS = %w[127.0.0.1 ::1 localhost].freeze

      def self.safe_transport?(uri)
        return true if uri.scheme == "https"
        return true if uri.scheme == "http" && LOOPBACK_HOSTS.include?(uri.host.to_s)

        false
      end

      def self.delete_json(uri, payload, token)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 30

        request = Net::HTTP::Delete.new(uri.request_uri, {
          "Content-Type" => "application/json",
          TOKEN_HEADER => token
        })
        request.body = payload.to_json

        response = http.request(request)
        [response.body, response.code.to_i]
      end

      def self.safe_parse(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        body.to_s
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
