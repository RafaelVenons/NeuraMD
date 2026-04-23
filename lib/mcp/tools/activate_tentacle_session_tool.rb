# frozen_string_literal: true

require "mcp"
require "net/http"
require "uri"
require "json"

module Mcp
  module Tools
    # Lets an agent (most often the Gerente) activate another agent's
    # tentacle session — the missing primitive that turned inbox
    # messages into dormant mail whenever the recipient had no live
    # session.
    #
    # Architectural note: this tool runs inside the MCP process spawned
    # by the agent's Claude Code, NOT inside the Puma web process.
    # `TentacleRuntime::SESSIONS` is a per-process Concurrent::Map, so
    # calling `TentacleRuntime.start` from here would create a session
    # that dies with the MCP process. Must go through HTTP to land the
    # session inside the web worker that serves the UI.
    class ActivateTentacleSessionTool < MCP::Tool
      tool_name "activate_tentacle_session"
      description <<~DESC.strip
        Activate a tentacle session for another agent's note. Spawns the session in the running neuramd-web process (authenticated via the shared agent S2S token). Use this after sending a message that needs immediate consumption — otherwise the recipient's inbox stays dormant until a human opens the tentacle in the UI.

        Returns `{activated: true, reused: <bool>, pid, started_at, command, slug}` on success; surfaces controller errors (401/403/422/409/503) as MCP errors with the original message.

        Target note must carry an `agente-*` tag (enforced server-side). `command` defaults to `claude`; `bash` is the only other accepted value. `initial_prompt` is optional and written to the session's stdin on first connect (≤2KB).
      DESC

      DEFAULT_COMMAND = "claude"
      ALLOWED_COMMANDS = %w[claude bash].freeze
      DEFAULT_BASE_URL = "http://127.0.0.1:3000"
      TOKEN_HEADER = "X-NeuraMD-Agent-Token"

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug of the recipient agent's note (its tentacle to activate)"},
          command: {type: "string", description: "Session command. Accepts 'claude' (default) or 'bash'."},
          initial_prompt: {type: "string", description: "Optional boot message written to stdin on first connect. ≤2KB."}
        },
        required: ["slug"]
      )

      def self.call(slug:, command: DEFAULT_COMMAND, initial_prompt: nil, server_context: nil)
        return error_response("slug cannot be blank") if slug.to_s.strip.empty?

        command_value = ALLOWED_COMMANDS.include?(command.to_s) ? command.to_s : DEFAULT_COMMAND

        token = resolve_token
        if token.blank?
          return error_response("S2S token not configured. Set ENV[\"AGENT_S2S_TOKEN\"] in the neuramd-web unit (systemd drop-in) or populate Rails.application.credentials.agent_s2s_token before retrying.")
        end

        uri = URI.parse("#{base_url}/api/s2s/tentacles/#{URI.encode_www_form_component(slug)}/activate")
        return error_response("refusing to send S2S token over plaintext HTTP to non-local host #{uri.host}; use https:// or a loopback address") unless safe_transport?(uri)

        payload = {command: command_value}
        payload[:initial_prompt] = initial_prompt if initial_prompt.present?

        body, status = post_json(uri, payload, token.to_s)
        parsed = safe_parse(body)

        if status.between?(200, 299)
          MCP::Tool::Response.new([{type: "text", text: parsed.to_json}])
        else
          message = parsed.is_a?(Hash) && parsed["error"].present? ? parsed["error"] : body.to_s
          error_response("activate failed (HTTP #{status}): #{message}")
        end
      rescue StandardError => e
        error_response("activate call raised #{e.class}: #{e.message}")
      end

      def self.base_url
        ENV.fetch("NEURAMD_S2S_URL", DEFAULT_BASE_URL)
      end

      # ENV wins over Rails.application.credentials for the same
      # reason as the server side: autodeploy's `git reset --hard`
      # would wipe an uncommitted credentials.yml.enc update, so the
      # production path is systemd drop-in env injection.
      def self.resolve_token
        env_value = ENV["AGENT_S2S_TOKEN"].to_s.strip
        return env_value unless env_value.empty?

        ::Rails.application.credentials.agent_s2s_token
      end

      # HTTPS is always fine; plain HTTP only to loopback. Prevents
      # accidentally shipping the bearer token to a non-local host
      # because of a misconfigured NEURAMD_S2S_URL override.
      LOOPBACK_HOSTS = %w[127.0.0.1 ::1 localhost].freeze

      def self.safe_transport?(uri)
        return true if uri.scheme == "https"
        return true if uri.scheme == "http" && LOOPBACK_HOSTS.include?(uri.host.to_s)

        false
      end

      def self.post_json(uri, payload, token)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri.request_uri, {
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
