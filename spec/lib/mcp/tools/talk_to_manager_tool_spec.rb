# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Tools::TalkToManagerTool do
  def make_note(slug:, title:)
    n = Note.create!(slug: slug, title: title)
    rev = n.note_revisions.create!(content_markdown: "body", revision_kind: :checkpoint)
    n.update!(head_revision_id: rev.id)
    n
  end

  let!(:gerente) { make_note(slug: "gerente", title: "Gerente") }
  let!(:agent_note) { make_note(slug: "claude-code-remoto", title: "Claude Code Remoto") }
  let(:token_record) do
    McpAccessToken.issue!(name: "remote", scopes: %w[read write tentacle], agent_note_id: agent_note.id).record
  end

  def context(token: token_record)
    { mcp_token: token }
  end

  def parse_response(resp)
    text = resp.to_h.dig(:content, 0, :text) || resp.to_h.dig("content", 0, "text")
    JSON.parse(text)
  rescue JSON::ParserError
    text
  end

  describe ".call" do
    it "creates a message from the token's agent_note to the gerente" do
      expect {
        resp = described_class.call(content: "ola gerente", server_context: context, wake: false)
        body = parse_response(resp)
        expect(body["sent"]).to be true
        expect(body["from_slug"]).to eq("claude-code-remoto")
        expect(body["to_slug"]).to eq("gerente")
        expect(body["message_id"]).to be_a(String)
      }.to change { AgentMessage.count }.by(1)
      msg = AgentMessage.last
      expect(msg.from_note).to eq(agent_note)
      expect(msg.to_note).to eq(gerente)
      expect(msg.content).to eq("ola gerente")
    end

    it "ignores from_slug and to_slug from arguments — identity comes from the token" do
      bystander = make_note(slug: "bystander", title: "Bystander")
      described_class.call(
        content: "spoof attempt",
        server_context: context,
        wake: false,
        from_slug: "gerente",
        to_slug: bystander.slug
      )
      msg = AgentMessage.last
      expect(msg.from_note).to eq(agent_note)
      expect(msg.to_note).to eq(gerente)
    end

    it "returns an error when server_context lacks mcp_token" do
      resp = described_class.call(content: "x", server_context: nil, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/token/i)
    end

    it "returns an error when the token has no agent_note bound" do
      anon = McpAccessToken.issue!(name: "anon", scopes: %w[tentacle]).record
      resp = described_class.call(content: "x", server_context: context(token: anon), wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/agent identity|agent_note|sem identidade/i)
    end

    it "returns an error when the gerente note doesn't exist" do
      gerente.destroy!
      resp = described_class.call(content: "x", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/gerente/i)
    end

    it "returns a Sender validation error when content is blank" do
      resp = described_class.call(content: "   ", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
    end

    context "with wake: true (default)" do
      it "calls the activator with the gerente slug" do
        expect(Mcp::Tools::ActivateTentacleSessionTool).to receive(:call) do |slug:, **_|
          expect(slug).to eq("gerente")
          MCP::Tool::Response.new([{type: "text", text: "{}"}])
        end
        described_class.call(content: "wake!", server_context: context)
      end

      it "still persists the message even if the activator raises" do
        allow(Mcp::Tools::ActivateTentacleSessionTool).to receive(:call).and_raise("S2S down")
        expect {
          resp = described_class.call(content: "durable", server_context: context)
          body = parse_response(resp)
          expect(body["sent"]).to be true
          expect(body["wake_warning"]).to match(/S2S down/)
        }.to change { AgentMessage.count }.by(1)
      end
    end
  end
end
