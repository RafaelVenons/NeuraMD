# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Tools::ReadManagerRepliesTool do
  def make_note(slug:, title:)
    n = Note.create!(slug: slug, title: title)
    rev = n.note_revisions.create!(content_markdown: "body", revision_kind: :checkpoint)
    n.update!(head_revision_id: rev.id)
    n
  end

  let!(:gerente) { make_note(slug: "gerente", title: "Gerente") }
  let!(:agent_a)  { make_note(slug: "agent-a", title: "Agent A") }
  let!(:agent_b)  { make_note(slug: "agent-b", title: "Agent B") }
  let(:token_a) { McpAccessToken.issue!(name: "a", scopes: %w[tentacle], agent_note_id: agent_a.id).record }
  let(:token_b) { McpAccessToken.issue!(name: "b", scopes: %w[tentacle], agent_note_id: agent_b.id).record }

  def context(token:)
    { mcp_token: token }
  end

  def parse_response(resp)
    text = resp.to_h.dig(:content, 0, :text) || resp.to_h.dig("content", 0, "text")
    JSON.parse(text)
  rescue JSON::ParserError
    text
  end

  describe ".call" do
    before do
      AgentMessages::Sender.call(from: gerente, to: agent_a, content: "reply for A 1")
      AgentMessages::Sender.call(from: gerente, to: agent_a, content: "reply for A 2")
      AgentMessages::Sender.call(from: gerente, to: agent_b, content: "reply for B")
    end

    it "returns only messages from the agent_note bound to the token" do
      resp = described_class.call(server_context: context(token: token_a))
      body = parse_response(resp)
      expect(body["count"]).to eq(2)
      expect(body["messages"].map { |m| m["content"] }).to contain_exactly("reply for A 1", "reply for A 2")
    end

    it "does not leak across tokens" do
      resp = described_class.call(server_context: context(token: token_b))
      body = parse_response(resp)
      expect(body["count"]).to eq(1)
      expect(body["messages"].first["content"]).to eq("reply for B")
    end

    it "respects only_pending: true (default) and excludes delivered messages" do
      AgentMessage.where(to_note: agent_a).update_all(delivered_at: Time.current)
      resp = described_class.call(server_context: context(token: token_a))
      body = parse_response(resp)
      expect(body["count"]).to eq(0)
    end

    it "marks pending messages delivered when mark_delivered: true" do
      expect {
        described_class.call(server_context: context(token: token_a), mark_delivered: true)
      }.to change { AgentMessage.where(to_note: agent_a, delivered_at: nil).count }.from(2).to(0)
    end

    it "errors when token lacks agent_note" do
      anon = McpAccessToken.issue!(name: "anon", scopes: %w[tentacle]).record
      resp = described_class.call(server_context: context(token: anon))
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/agent identity|agent_note|sem identidade/i)
    end

    it "errors when server_context lacks mcp_token" do
      resp = described_class.call(server_context: nil)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
    end
  end
end
