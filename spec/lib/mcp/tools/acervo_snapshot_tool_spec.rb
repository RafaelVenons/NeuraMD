# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::Tools::AcervoSnapshotTool do
  def make_note(slug:, title:, content: "body line\nsecond line\nthird line\nfourth line\nfifth line\nsixth line\nseventh line\neighth line\nninth line\ntenth line\neleventh line", tags: [])
    n = Note.create!(slug: slug, title: title)
    rev = n.note_revisions.create!(content_markdown: content, revision_kind: :checkpoint)
    n.update!(head_revision_id: rev.id)
    tags.each do |tag_name|
      tag = Tag.find_or_create_by!(name: tag_name, tag_scope: "note")
      NoteTag.find_or_create_by!(note: n, tag: tag)
    end
    n
  end

  let!(:fresh) { make_note(slug: "fresh-note", title: "Fresh", tags: %w[topic-x]) }
  let!(:older) do
    n = make_note(slug: "older", title: "Older", tags: %w[topic-y])
    n.head_revision.update_columns(created_at: 3.days.ago)
    n
  end
  let!(:anemic) { make_note(slug: "skinny", title: "Skinny", content: "one liner", tags: %w[topic-x]) }

  def parse(resp)
    text = resp.to_h.dig(:content, 0, :text) || resp.to_h.dig("content", 0, "text")
    JSON.parse(text)
  end

  describe ".call" do
    it "returns recent_changes within the window" do
      payload = parse(described_class.call(since_hours: 24, limit_per_section: 5))
      slugs = payload["recent_changes"].map { |n| n["slug"] }
      expect(slugs).to include("fresh-note", "skinny")
      expect(slugs).not_to include("older")
    end

    it "returns anemic_notes summary (count + sample slugs)" do
      payload = parse(described_class.call)
      expect(payload["anemic_notes"]["count"]).to be >= 1
      expect(payload["anemic_notes"]["sample"].map { |n| n["slug"] }).to include("skinny")
    end

    it "returns top_tags by note count" do
      payload = parse(described_class.call(limit_per_section: 5))
      tag_names = payload["top_tags"].map { |t| t["name"] }
      expect(tag_names).to include("topic-x")
      topic_x = payload["top_tags"].find { |t| t["name"] == "topic-x" }
      expect(topic_x["note_count"]).to be >= 2
    end

    it "includes inbox_pending when caller has a token with agent_note" do
      agent_note = make_note(slug: "agent-bot", title: "Agent")
      sender = make_note(slug: "sender", title: "Sender")
      AgentMessages::Sender.call(from: sender, to: agent_note, content: "ping1")
      AgentMessages::Sender.call(from: sender, to: agent_note, content: "ping2")
      token = McpAccessToken.issue!(name: "t", scopes: %w[read], agent_note_id: agent_note.id).record

      payload = parse(described_class.call(server_context: {mcp_token: token}))
      expect(payload["inbox_pending"]).to eq("agent_slug" => "agent-bot", "count" => 2)
    end

    it "omits inbox_pending when token has no agent_note" do
      anon = McpAccessToken.issue!(name: "anon", scopes: %w[read]).record
      payload = parse(described_class.call(server_context: {mcp_token: anon}))
      expect(payload).not_to have_key("inbox_pending")
    end

    it "omits inbox_pending when no server_context" do
      payload = parse(described_class.call(server_context: nil))
      expect(payload).not_to have_key("inbox_pending")
    end

    it "respects since_hours" do
      payload = parse(described_class.call(since_hours: 96))
      slugs = payload["recent_changes"].map { |n| n["slug"] }
      expect(slugs).to include("older")
    end
  end
end
