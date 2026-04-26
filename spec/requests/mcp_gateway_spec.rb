# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Gateway", type: :request do
  let(:read_token_issued) { McpAccessToken.issue!(name: "read-only", scopes: %w[read]) }
  let(:read_write_issued) { McpAccessToken.issue!(name: "rw", scopes: %w[read write]) }

  def bearer(plaintext)
    { "Authorization" => "Bearer #{plaintext}", "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def jsonrpc(method, params: nil, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method }
    body[:params] = params if params
    body.to_json
  end

  def call_payload(tool_name, args = {})
    jsonrpc("tools/call", params: { name: tool_name, arguments: args })
  end

  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    RemoteMcpGateway.reset!
  end

  describe "auth" do
    it "rejects missing Authorization header with -32001" do
      post "/mcp", params: jsonrpc("initialize"), headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_001)
    end

    it "rejects unknown bearer token" do
      post "/mcp", params: jsonrpc("initialize"), headers: bearer("nope-not-a-real-token")
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects revoked tokens" do
      read_token_issued.record.update!(revoked_at: Time.current)
      post "/mcp", params: jsonrpc("initialize"), headers: bearer(read_token_issued.plaintext)
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a valid token and touches last_used_at" do
      expect {
        post "/mcp", params: jsonrpc("initialize"), headers: bearer(read_token_issued.plaintext)
      }.to change { read_token_issued.record.reload.last_used_at }.from(nil)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "tools/list" do
    it "lists only whitelisted tools" do
      post "/mcp", params: jsonrpc("tools/list"), headers: bearer(read_token_issued.plaintext)
      expect(response).to have_http_status(:ok)
      tools = JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
      expect(tools).to include("search_notes", "read_note", "create_note")
      # Tentacle tools are commented out by default
      expect(tools).not_to include("send_agent_message", "spawn_child_tentacle")
    end
  end

  describe "scope enforcement" do
    it "rejects a write tool when token only has :read" do
      post "/mcp", params: call_payload("create_note", title: "x", content_markdown: "y"),
           headers: bearer(read_token_issued.plaintext)
      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq(-32_001)
      expect(body.dig("error", "message")).to match(/scope/i)
    end

    it "allows the same call when the token has :write" do
      post "/mcp", params: call_payload("create_note", title: "spec note", content_markdown: "[[Especialista NeuraMD|f:e0585b08-5514-49ea-9954-a9a2d776530a]]\n\nbody"),
           headers: bearer(read_write_issued.plaintext)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("error")).to be_nil
    end
  end

  describe "non-whitelisted tool" do
    it "returns -32601 for tools not exposed remotely" do
      post "/mcp", params: call_payload("send_agent_message", from: "x", to: "y", body: "z"),
           headers: bearer(read_write_issued.plaintext)
      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq(-32_601)
      expect(body.dig("error", "message")).to match(/not exposed/i)
    end
  end

  describe "malformed payload" do
    it "passes garbage through to transport which returns parse error" do
      post "/mcp", params: "{not json", headers: bearer(read_token_issued.plaintext)
      # Transport handles JSON parse failures internally
      expect(response.status).to be_between(200, 500)
      expect(response.body).to include("error")
    end
  end

  describe "rate limit" do
    around do |example|
      original = ENV["NEURAMD_MCP_RATE_LIMIT_PER_MIN"]
      ENV["NEURAMD_MCP_RATE_LIMIT_PER_MIN"] = "2"
      RemoteMcpGateway.reset!
      example.run
      ENV["NEURAMD_MCP_RATE_LIMIT_PER_MIN"] = original
      RemoteMcpGateway.reset!
    end

    it "returns 429 after exceeding the per-token throttle" do
      3.times { post "/mcp", params: jsonrpc("tools/list"), headers: bearer(read_token_issued.plaintext) }
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq(-32_000)
    end
  end

  describe "timeout" do
    around do |example|
      original = ENV["NEURAMD_MCP_CALL_TIMEOUT_SECONDS"]
      ENV["NEURAMD_MCP_CALL_TIMEOUT_SECONDS"] = "0.05"
      RemoteMcpGateway.reset!
      example.run
      ENV["NEURAMD_MCP_CALL_TIMEOUT_SECONDS"] = original
      RemoteMcpGateway.reset!
    end

    it "responds with -32603 when the call times out" do
      allow(RemoteMcpGateway.transport).to receive(:call) { sleep 0.5 }
      post "/mcp", params: jsonrpc("tools/list"), headers: bearer(read_token_issued.plaintext)
      expect(response).to have_http_status(:gateway_timeout)
      expect(JSON.parse(response.body).dig("error", "code")).to eq(-32_603)
    end
  end

  describe "DELETE /mcp" do
    it "is allowed (stateless transport returns 200)" do
      delete "/mcp", headers: bearer(read_token_issued.plaintext)
      expect(response).to have_http_status(:ok)
    end
  end
end
