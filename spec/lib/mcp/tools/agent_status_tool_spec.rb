# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Tools::AgentStatusTool do
  def make_note(slug:, title:, tags: [])
    n = Note.create!(slug: slug, title: title)
    rev = n.note_revisions.create!(content_markdown: "body", revision_kind: :checkpoint)
    n.update!(head_revision_id: rev.id)
    tags.each do |t|
      tag = Tag.find_or_create_by!(name: t, tag_scope: "note")
      NoteTag.find_or_create_by!(note: n, tag: tag)
    end
    n
  end

  let!(:agent) { make_note(slug: "gerente", title: "Gerente", tags: %w[agente agente-gerente]) }
  let!(:other) { make_note(slug: "other-agent", title: "Other") }

  def parse(resp)
    text = resp.to_h.dig(:content, 0, :text) || resp.to_h.dig("content", 0, "text")
    JSON.parse(text)
  end

  describe ".call" do
    it "returns identity + zero counts when nothing happened yet" do
      payload = parse(described_class.call(slug: "gerente"))
      expect(payload).to include(
        "slug" => "gerente",
        "title" => "Gerente",
        "alive_sessions" => 0,
        "inbox_pending_count" => 0
      )
      expect(payload["tags"]).to include("agente-gerente")
    end

    it "counts alive tentacle sessions for the note" do
      TentacleSession.create!(
        tentacle_note_id: agent.id,
        command: "claude",
        dtach_socket: "/tmp/sock-#{SecureRandom.hex(4)}",
        started_at: 1.minute.ago,
        last_seen_at: 10.seconds.ago,
        status: "alive"
      )
      TentacleSession.create!(
        tentacle_note_id: agent.id,
        command: "claude",
        dtach_socket: "/tmp/sock-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        ended_at: 1.hour.ago,
        status: "exited"
      )
      payload = parse(described_class.call(slug: "gerente"))
      expect(payload["alive_sessions"]).to eq(1)
      expect(payload["last_seen_at"]).to be_a(String)
    end

    it "counts pending inbox + reports last inbox/outbox timestamps" do
      AgentMessages::Sender.call(from: other, to: agent, content: "ping")
      AgentMessages::Sender.call(from: other, to: agent, content: "ping2")
      AgentMessages::Sender.call(from: agent, to: other, content: "reply")

      payload = parse(described_class.call(slug: "gerente"))
      expect(payload["inbox_pending_count"]).to eq(2)
      expect(payload["last_inbox_at"]).to be_a(String)
      expect(payload["last_outbox_at"]).to be_a(String)
    end

    it "returns an error for unknown slug" do
      resp = described_class.call(slug: "ghost")
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
      text = resp.to_h.dig(:content, 0, :text) || resp.to_h.dig("content", 0, "text")
      expect(text).to match(/not found/i)
    end

    it "returns an error when slug is blank" do
      resp = described_class.call(slug: "  ")
      expect(resp.to_h[:isError] || resp.to_h["isError"]).to be true
    end

    context "with a runtime in-memory session (PTY mode — no DB record)" do
      around do |example|
        example.run
      ensure
        TentacleRuntime::SESSIONS.delete(agent.id)
      end

      it "reports alive_sessions=1 + last_started_at from the runtime when no DB row exists" do
        # PTY-mode spawns never call persist_tentacle_session_record!, so
        # TentacleRuntime::SESSIONS is the only source of truth. Without
        # this fallback, agent_status was reporting 0/null for live agents.
        started = 30.seconds.ago
        runtime_session = instance_double(
          TentacleRuntime::Session,
          alive?: true,
          started_at: started
        )
        TentacleRuntime::SESSIONS[agent.id] = runtime_session

        payload = parse(described_class.call(slug: "gerente"))
        expect(payload["alive_sessions"]).to eq(1)
        expect(payload["last_started_at"]).to be_a(String)
        expect(Time.iso8601(payload["last_started_at"])).to be_within(1).of(started)
        expect(payload["last_seen_at"]).to be_a(String)
      end

      it "still falls back to DB when no runtime entry but DB has alive row (dtach reattach scenario)" do
        TentacleSession.create!(
          tentacle_note_id: agent.id,
          command: "claude",
          dtach_socket: "/tmp/sock-#{SecureRandom.hex(4)}",
          started_at: 5.minutes.ago,
          last_seen_at: 10.seconds.ago,
          status: "alive"
        )

        payload = parse(described_class.call(slug: "gerente"))
        expect(payload["alive_sessions"]).to eq(1)
        expect(payload["last_seen_at"]).to be_a(String)
        expect(payload["last_started_at"]).to be_a(String)
      end

      it "returns 0 alive when runtime entry exists but Session#alive? is false" do
        runtime_session = instance_double(
          TentacleRuntime::Session,
          alive?: false,
          started_at: 1.hour.ago
        )
        TentacleRuntime::SESSIONS[agent.id] = runtime_session

        payload = parse(described_class.call(slug: "gerente"))
        expect(payload["alive_sessions"]).to eq(0)
      end
    end
  end
end
