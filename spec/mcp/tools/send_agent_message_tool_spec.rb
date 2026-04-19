require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::SendAgentMessageTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("send_agent_message")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:from) { create(:note, :with_head_revision, title: "Sender") }
    let!(:to)   { create(:note, :with_head_revision, title: "Recipient") }

    it "persists a message and returns metadata" do
      response = described_class.call(from_slug: from.slug, to_slug: to.slug, content: "hello")
      data = JSON.parse(response.content.first[:text])

      expect(data["sent"]).to be true
      expect(data["from_slug"]).to eq(from.slug)
      expect(data["to_slug"]).to eq(to.slug)
      expect(data["content_bytes"]).to eq(5)
      expect(data["truncated"]).to be false
      expect(AgentMessage.find(data["message_id"]).content).to eq("hello")
    end

    it "returns error when sender does not exist" do
      response = described_class.call(from_slug: "missing", to_slug: to.slug, content: "x")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Sender note not found")
    end

    it "returns error when recipient does not exist" do
      response = described_class.call(from_slug: from.slug, to_slug: "missing", content: "x")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Recipient note not found")
    end

    it "returns error for self-addressed messages" do
      response = described_class.call(from_slug: from.slug, to_slug: from.slug, content: "x")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("cannot send to self")
    end

    it "returns error for blank content" do
      response = described_class.call(from_slug: from.slug, to_slug: to.slug, content: "   ")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("blank")
    end

    it "flags truncation when content exceeds the cap" do
      big = "x" * (AgentMessages::Sender::MAX_CONTENT_BYTES + 100)
      response = described_class.call(from_slug: from.slug, to_slug: to.slug, content: big)
      data = JSON.parse(response.content.first[:text])

      expect(data["truncated"]).to be true
    end
  end
end
