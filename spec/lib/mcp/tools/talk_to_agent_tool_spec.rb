# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Tools::TalkToAgentTool do
  def make_note(slug:, title:, tags: [])
    n = Note.create!(slug: slug, title: title)
    rev = n.note_revisions.create!(content_markdown: "body", revision_kind: :checkpoint)
    n.update!(head_revision_id: rev.id)
    tags.each do |tag_name|
      tag = Tag.find_or_create_by!(name: tag_name, tag_scope: "note")
      NoteTag.find_or_create_by!(note: n, tag: tag)
    end
    n
  end

  let!(:gerente) { make_note(slug: "gerente", title: "Gerente", tags: %w[agente agente-gerente]) }
  let!(:uxui) { make_note(slug: "uxui", title: "UX/UI", tags: %w[agente agente-uxui]) }
  let!(:plain_note) { make_note(slug: "plain", title: "Just a note") }
  let!(:agent_note) { make_note(slug: "claude-code-remoto", title: "Claude Code Remoto", tags: %w[agente agente-remote]) }
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
    it "creates a message to any agent note carrying an agente-* tag" do
      expect {
        resp = described_class.call(slug: "uxui", content: "olá ux", server_context: context, wake: false)
        body = parse_response(resp)
        expect(body["sent"]).to be true
        expect(body["from_slug"]).to eq("claude-code-remoto")
        expect(body["to_slug"]).to eq("uxui")
      }.to change { AgentMessage.count }.by(1)
      msg = AgentMessage.last
      expect(msg.from_note).to eq(agent_note)
      expect(msg.to_note).to eq(uxui)
    end

    it "still routes to the gerente when slug=gerente" do
      described_class.call(slug: "gerente", content: "olá chefe", server_context: context, wake: false)
      msg = AgentMessage.last
      expect(msg.to_note).to eq(gerente)
    end

    it "ignores from_slug from arguments — sender locked to the token" do
      described_class.call(
        slug: "uxui",
        content: "spoof attempt",
        server_context: context,
        wake: false,
        from_slug: "gerente"
      )
      expect(AgentMessage.last.from_note).to eq(agent_note)
    end

    it "rejects recipients without an agente-* tag" do
      resp = described_class.call(slug: "plain", content: "hi", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/not an agent|agente-/i)
    end

    it "returns an error when slug is blank" do
      resp = described_class.call(slug: "  ", content: "x", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
    end

    it "returns an error when recipient note doesn't exist" do
      resp = described_class.call(slug: "ghost", content: "x", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/not found/i)
    end

    it "returns an error when server_context lacks mcp_token" do
      resp = described_class.call(slug: "uxui", content: "x", server_context: nil, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/token/i)
    end

    it "returns an error when the token has no agent_note bound" do
      anon = McpAccessToken.issue!(name: "anon", scopes: %w[tentacle]).record
      resp = described_class.call(slug: "uxui", content: "x", server_context: context(token: anon), wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      expect(parse_response(resp)).to match(/agent identity|agent_note|sem identidade/i)
    end

    it "rejects sending to self (Sender validation)" do
      resp = described_class.call(slug: "claude-code-remoto", content: "x", server_context: context, wake: false)
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
    end

    context "with wake: true (default)" do
      it "calls the activator with the recipient's slug + initial_prompt mentioning sender, content, and inbox tool" do
        captured = {}
        expect(Mcp::Tools::ActivateTentacleSessionTool).to receive(:call) do |**kwargs|
          captured = kwargs
          MCP::Tool::Response.new([{type: "text", text: "{}"}])
        end
        described_class.call(slug: "uxui", content: "audita PR #50 e me responde", server_context: context)

        expect(captured[:slug]).to eq("uxui")
        prompt = captured[:initial_prompt]
        expect(prompt).to be_a(String)
        expect(prompt).to include("claude-code-remoto") # sender slug
        expect(prompt).to include("audita PR #50")      # content snippet
        expect(prompt).to include("read_agent_inbox")   # tool ponteiro
        expect(prompt).to include("uxui")               # recipient slug (pra slug= no comando)
      end

      it "truncates long content in the prompt to stay under the 2KB BootConfig cap" do
        big_content = "x" * 5_000
        captured = {}
        allow(Mcp::Tools::ActivateTentacleSessionTool).to receive(:call) do |**kwargs|
          captured = kwargs
          MCP::Tool::Response.new([{type: "text", text: "{}"}])
        end
        described_class.call(slug: "uxui", content: big_content, server_context: context)

        expect(captured[:initial_prompt].bytesize).to be <= ::Tentacles::BootConfig::INITIAL_PROMPT_MAX_BYTES
      end

      it "still persists the message even if the activator raises" do
        allow(Mcp::Tools::ActivateTentacleSessionTool).to receive(:call).and_raise("S2S down")
        expect {
          resp = described_class.call(slug: "uxui", content: "durable", server_context: context)
          body = parse_response(resp)
          expect(body["sent"]).to be true
          expect(body["wake_warning"]).to match(/S2S down/)
        }.to change { AgentMessage.count }.by(1)
      end
    end
  end
end
