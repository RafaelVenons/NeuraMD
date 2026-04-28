require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::TerminateTentacleSessionTool do
  let(:token) { "stubbed-token-#{SecureRandom.hex(8)}" }

  before do
    credentials = Rails.application.credentials
    allow(credentials).to receive(:agent_s2s_token).and_return(token)
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("terminate_tentacle_session")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    it "issues DELETE to the S2S endpoint with the token header and returns the parsed body" do
      captured = {}
      allow(described_class).to receive(:delete_json) do |uri, payload, auth_token|
        captured[:uri] = uri
        captured[:payload] = payload
        captured[:token] = auth_token
        [{
          terminated: true,
          stopped: true,
          slug: "agenda",
          tentacle_id: "abc",
          pid: 1234,
          escalated_to_kill: false,
          ended_at: Time.current.utc.iso8601
        }.to_json, 200]
      end

      response = described_class.call(slug: "agenda")
      data = JSON.parse(response.content.first[:text])

      expect(captured[:token]).to eq(token)
      expect(captured[:uri].path).to eq("/api/s2s/tentacles/agenda")
      expect(captured[:payload]).to eq({force: false})
      expect(data).to include(
        "terminated" => true,
        "pid" => 1234,
        "escalated_to_kill" => false
      )
    end

    it "passes force: true through when requested" do
      payloads = []
      allow(described_class).to receive(:delete_json) do |_uri, payload, _token|
        payloads << payload
        [{terminated: true, escalated_to_kill: true}.to_json, 200]
      end

      described_class.call(slug: "qa", force: true)
      expect(payloads.first).to eq({force: true})
    end

    it "is idempotent on no-session: returns success with terminated: false" do
      allow(described_class).to receive(:delete_json).and_return(
        [{terminated: false, reason: "no_session", slug: "agenda"}.to_json, 200]
      )

      response = described_class.call(slug: "agenda")
      expect(response.error?).to be(false)
      data = JSON.parse(response.content.first[:text])
      expect(data["terminated"]).to be(false)
      expect(data["reason"]).to eq("no_session")
    end

    it "returns error when slug is blank" do
      response = described_class.call(slug: "")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("slug cannot be blank")
    end

    it "returns error when S2S token credential is missing" do
      credentials = Rails.application.credentials
      allow(credentials).to receive(:agent_s2s_token).and_return(nil)

      response = described_class.call(slug: "agenda")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("S2S token not configured")
    end

    it "surfaces upstream 401 as a tool error" do
      allow(described_class).to receive(:delete_json).and_return(
        [{error: "invalid token"}.to_json, 401]
      )

      response = described_class.call(slug: "agenda")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("HTTP 401", "invalid token")
    end

    it "surfaces upstream 403 (non-agent tag) as a tool error" do
      allow(described_class).to receive(:delete_json).and_return(
        [{error: "note does not carry an agent tag"}.to_json, 403]
      )

      response = described_class.call(slug: "bookshelf")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("HTTP 403", "agent tag")
    end

    it "handles network errors gracefully" do
      allow(described_class).to receive(:delete_json).and_raise(Errno::ECONNREFUSED.new("connection refused"))

      response = described_class.call(slug: "agenda")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("Errno::ECONNREFUSED")
    end

    it "refuses to send the S2S token over plain HTTP to non-loopback hosts" do
      ENV["NEURAMD_S2S_URL"] = "http://other.local:9999"
      expect(described_class).not_to receive(:delete_json)

      response = described_class.call(slug: "agenda")
      expect(response.error?).to be(true)
      expect(response.content.first[:text]).to include("plaintext HTTP", "other.local")
    ensure
      ENV.delete("NEURAMD_S2S_URL")
    end

    it "allows HTTPS to non-loopback hosts" do
      ENV["NEURAMD_S2S_URL"] = "https://other.local:443"
      captured_uri = nil
      allow(described_class).to receive(:delete_json) do |uri, _payload, _token|
        captured_uri = uri
        [{terminated: true}.to_json, 200]
      end

      described_class.call(slug: "agenda")
      expect(captured_uri.scheme).to eq("https")
    ensure
      ENV.delete("NEURAMD_S2S_URL")
    end
  end
end
