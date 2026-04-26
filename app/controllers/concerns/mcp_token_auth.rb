# frozen_string_literal: true

module McpTokenAuth
  extend ActiveSupport::Concern

  private

  def authenticate_mcp_token!
    plaintext = extract_mcp_bearer_token
    token = McpAccessToken.authenticate(plaintext) if plaintext.present?

    if token.nil?
      render_jsonrpc_error(code: -32_001, message: "Unauthorized", status: :unauthorized)
      return false
    end

    @current_mcp_token = token
    true
  end

  def current_mcp_token
    @current_mcp_token
  end

  def extract_mcp_bearer_token
    header = request.headers["Authorization"].to_s
    match = header.match(/\ABearer\s+(?<token>.+)\z/)
    match ? match[:token].strip : nil
  end

  def render_jsonrpc_error(code:, message:, status:, request_id: nil)
    payload = {
      jsonrpc: "2.0",
      id: request_id,
      error: { code: code, message: message }
    }
    render json: payload, status: status
  end
end
