# frozen_string_literal: true

require "yaml"
require "rack/attack"

# Loads the Remote MCP Gateway whitelist + scope map from
# config/mcp_remote.yml (falls back to .yml.example when the operator
# hasn't customised). Exposed as RemoteMcpGateway::Config.

module RemoteMcpGateway
  class Config
    DEFAULT_RATE_LIMIT_PER_MIN = 60
    DEFAULT_CALL_TIMEOUT_SECONDS = 30
    KNOWN_SCOPES = %w[read write tentacle].freeze

    attr_reader :tool_classes, :scope_map, :rate_limit_per_min, :call_timeout_seconds

    def self.load!
      path = locate_config_file
      raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
      new(raw)
    end

    def self.locate_config_file
      custom = Rails.root.join("config/mcp_remote.yml")
      return custom if File.exist?(custom)
      Rails.root.join("config/mcp_remote.yml.example")
    end

    def initialize(raw)
      tools = raw.fetch("tools", {}) || {}
      @tool_classes = {}
      @scope_map = {}

      tools.each do |tool_name, entry|
        klass_name = entry.fetch("class")
        scope = entry.fetch("scope", "read").to_s
        unless KNOWN_SCOPES.include?(scope)
          raise ArgumentError, "mcp_remote.yml: tool #{tool_name.inspect} has unknown scope #{scope.inspect}"
        end
        @tool_classes[tool_name.to_s] = klass_name.constantize
        @scope_map[tool_name.to_s] = scope
      end

      env_rl = ENV["NEURAMD_MCP_RATE_LIMIT_PER_MIN"]
      @rate_limit_per_min = (env_rl.presence || raw["rate_limit_per_min"] || DEFAULT_RATE_LIMIT_PER_MIN).to_i
      env_to = ENV["NEURAMD_MCP_CALL_TIMEOUT_SECONDS"]
      @call_timeout_seconds = (env_to.presence || raw["call_timeout_seconds"] || DEFAULT_CALL_TIMEOUT_SECONDS).to_f
    end

    def required_scope_for(tool_name)
      scope_map[tool_name.to_s]
    end

    def exposed_tool?(tool_name)
      tool_classes.key?(tool_name.to_s)
    end

    def tools
      tool_classes.values
    end
  end

  class << self
    def config
      @config ||= Config.load!
    end

    def reset!
      @config = nil
    end

    # Builds a fresh MCP::Server + StreamableHTTPTransport per request.
    # Per-request avoids races on `Server#server_context` between Puma
    # threads — the token identity must travel with the call. Stateless
    # mode means there's no session state to lose between requests.
    def build_for(mcp_token)
      server = MCP::Server.new(
        name: "neuramd-remote",
        version: "1.0.0",
        tools: config.tools,
        server_context: { mcp_token: mcp_token }
      )
      MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true
      )
    end
  end
end

Rails.application.config.to_prepare do
  RemoteMcpGateway.reset!
  RemoteMcpGateway.config # eager-load and validate at boot
end

# Rack::Attack: per-token throttle. Token id is resolved from the
# Authorization bearer header by hashing the plaintext (avoids touching
# the DB inside the throttle path). Unknown tokens fall through to the
# 401 path in McpController.
Rack::Attack.throttle("mcp/token", limit: ->(_req) { RemoteMcpGateway.config.rate_limit_per_min }, period: 60) do |req|
  next unless req.path == "/mcp"
  header = req.env["HTTP_AUTHORIZATION"].to_s
  match = header.match(/\ABearer\s+(?<token>.+)\z/)
  next unless match
  Digest::SHA256.hexdigest(match[:token].strip)
end

# Rack::Attack returns plain 429 by default. Use a JSON-RPC-shaped body
# so MCP clients see a parseable error rather than HTML.
Rack::Attack.throttled_responder = lambda do |request|
  retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i
  body = {
    jsonrpc: "2.0",
    id: nil,
    error: { code: -32_000, message: "Rate limit exceeded" }
  }.to_json
  [429, { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s }, [body]]
end

Rails.application.config.middleware.use Rack::Attack
