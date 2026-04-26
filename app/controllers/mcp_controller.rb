# frozen_string_literal: true

# Remote MCP Gateway entry point. Wraps the official mcp gem's
# StreamableHTTPTransport with bearer-token auth, scope enforcement
# from config/mcp_remote.yml, and a per-call timeout.
#
# Stateless mode is intentional — every request authenticates
# independently, so there's no session affinity to manage. JSON-only
# response keeps the response a single chunk (no SSE plumbing in Rails).
class McpController < ActionController::API
  include McpTokenAuth

  before_action :authenticate_mcp_token!
  before_action :enforce_scope!, only: :handle

  def handle
    request.body.rewind
    current_mcp_token.touch_used!

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timeout = RemoteMcpGateway.config.call_timeout_seconds
    status, headers, body = nil

    Timeout.timeout(timeout, McpCallTimeout) do
      status, headers, body = RemoteMcpGateway.transport.call(request.env)
    end

    log_call(status: status, started: started, error: nil)
    relay(status, headers, body)
  rescue McpCallTimeout
    log_call(status: 504, started: started, error: "timeout")
    render_jsonrpc_error(
      code: -32_603,
      message: "Tool call exceeded #{timeout}s timeout",
      status: :gateway_timeout,
      request_id: jsonrpc_request_id
    )
  rescue StandardError => e
    log_call(status: 500, started: started, error: "#{e.class}: #{e.message}")
    render_jsonrpc_error(
      code: -32_603,
      message: "Internal server error",
      status: :internal_server_error,
      request_id: jsonrpc_request_id
    )
  end

  private

  class McpCallTimeout < StandardError; end

  def enforce_scope!
    return true unless request.post?
    body = parsed_body
    return true unless body.is_a?(Hash) && body["method"] == "tools/call"

    tool_name = body.dig("params", "name").to_s
    unless RemoteMcpGateway.config.exposed_tool?(tool_name)
      render_jsonrpc_error(
        code: -32_601,
        message: "Tool not exposed remotely: #{tool_name}",
        status: :forbidden,
        request_id: body["id"]
      )
      return false
    end

    required = RemoteMcpGateway.config.required_scope_for(tool_name)
    unless current_mcp_token.scope?(required)
      render_jsonrpc_error(
        code: -32_001,
        message: "Insufficient scope: requires '#{required}'",
        status: :forbidden,
        request_id: body["id"]
      )
      return false
    end

    true
  end

  def parsed_body
    @parsed_body ||= begin
      request.body.rewind
      raw = request.body.read
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    ensure
      request.body.rewind
    end
  end

  def jsonrpc_request_id
    body = parsed_body
    body.is_a?(Hash) ? body["id"] : nil
  end

  def relay(status, headers, body)
    headers&.each { |k, v| response.headers[k] = v }
    self.response_body = body.respond_to?(:join) ? body.join : body.to_s
    self.status = status
  end

  def log_call(status:, started:, error:)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    body = parsed_body
    Rails.logger.tagged("mcp") do
      Rails.logger.info({
        token_id: current_mcp_token&.id,
        tool: body.is_a?(Hash) ? body.dig("params", "name") : nil,
        method: body.is_a?(Hash) ? body["method"] : nil,
        status: status,
        latency_ms: elapsed_ms,
        error: error
      }.compact.to_json)
    end
  end
end
