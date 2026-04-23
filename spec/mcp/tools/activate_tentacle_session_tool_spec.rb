require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ActivateTentacleSessionTool do
  let(:token) { "stubbed-token-#{SecureRandom.hex(8)}" }

  before do
    credentials = Rails.application.credentials
    allow(credentials).to receive(:agent_s2s_token).and_return(token)
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("activate_tentacle_session")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    it "posts to the S2S endpoint with the token header and returns the parsed body" do
      captured = {}
      allow(described_class).to receive(:post_json) do |uri, payload, auth_token|
        captured[:uri] = uri
        captured[:payload] = payload
        captured[:token] = auth_token
        [{activated: true, reused: false, pid: 999, slug: "especialista-neuramd"}.to_json, 201]
      end

      response = described_class.call(slug: "especialista-neuramd", command: "claude")
      data = JSON.parse(response.content.first[:text])

      expect(captured[:token]).to eq(token)
      expect(captured[:uri].path).to eq("/api/s2s/tentacles/especialista-neuramd/activate")
      expect(captured[:payload]).to eq({command: "claude"})
      expect(data).to include("activated" => true, "reused" => false, "pid" => 999)
    end

    it "passes through initial_prompt when provided" do
      payloads = []
      allow(described_class).to receive(:post_json) do |_uri, payload, _token|
        payloads << payload
        [{activated: true, reused: true}.to_json, 200]
      end

      described_class.call(slug: "uxui", command: "claude", initial_prompt: "wake up")
      expect(payloads.first).to eq({command: "claude", initial_prompt: "wake up"})
    end

    it "defaults command to claude and coerces unknown commands to claude" do
      payloads = []
      allow(described_class).to receive(:post_json) do |_uri, payload, _token|
        payloads << payload
        [{activated: true}.to_json, 201]
      end

      described_class.call(slug: "gerente", command: "python-repl")
      expect(payloads.first[:command]).to eq("claude")
    end

    it "returns error when slug is blank" do
      response = described_class.call(slug: "")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("slug cannot be blank")
    end

    it "returns error when S2S token credential is missing" do
      credentials = Rails.application.credentials
      allow(credentials).to receive(:agent_s2s_token).and_return(nil)

      response = described_class.call(slug: "gerente")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("S2S token not configured")
    end

    it "surfaces upstream 401 as a tool error" do
      allow(described_class).to receive(:post_json).and_return(
        [{error: "invalid token"}.to_json, 401]
      )

      response = described_class.call(slug: "gerente")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("HTTP 401", "invalid token")
    end

    it "surfaces upstream 403 (non-agent tag) as a tool error" do
      allow(described_class).to receive(:post_json).and_return(
        [{error: "note does not carry an agent tag"}.to_json, 403]
      )

      response = described_class.call(slug: "bookshelf")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("HTTP 403", "agent tag")
    end

    it "surfaces upstream 422 as a tool error" do
      allow(described_class).to receive(:post_json).and_return(
        [{error: "tentacle_workspace: workspace not found: evil"}.to_json, 422]
      )

      response = described_class.call(slug: "uxui")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("HTTP 422", "workspace not found")
    end

    it "handles network errors gracefully" do
      allow(described_class).to receive(:post_json).and_raise(Errno::ECONNREFUSED.new("connection refused"))

      response = described_class.call(slug: "gerente")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("Errno::ECONNREFUSED")
    end

    it "honors NEURAMD_S2S_URL env override" do
      ENV["NEURAMD_S2S_URL"] = "http://other.local:9999"
      captured_uri = nil
      allow(described_class).to receive(:post_json) do |uri, _payload, _token|
        captured_uri = uri
        [{activated: true}.to_json, 201]
      end

      described_class.call(slug: "gerente")
      expect(captured_uri.to_s).to start_with("http://other.local:9999")
    ensure
      ENV.delete("NEURAMD_S2S_URL")
    end
  end
end
