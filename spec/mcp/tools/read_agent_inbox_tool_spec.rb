require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ReadAgentInboxTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("read_agent_inbox")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:owner)  { create(:note, :with_head_revision, title: "Owner") }
    let!(:other)  { create(:note, :with_head_revision, title: "Other") }

    def send_msg(to: owner, from: other, delivered: false)
      attrs = {from_note: from, to_note: to, content: "msg-#{SecureRandom.hex(2)}"}
      attrs[:delivered_at] = 1.minute.ago if delivered
      AgentMessage.create!(attrs)
    end

    it "returns inbox messages newest first" do
      older = send_msg
      older.update!(created_at: 2.hours.ago)
      newer = send_msg

      response = described_class.call(slug: owner.slug)
      data = JSON.parse(response.content.first[:text])

      expect(data["count"]).to eq(2)
      expect(data["messages"].map { |m| m["id"] }).to eq([newer.id, older.id])
      expect(data["marked_delivered"]).to eq(0)
    end

    it "filters to pending when only_pending is true" do
      delivered = send_msg(delivered: true)
      pending   = send_msg

      response = described_class.call(slug: owner.slug, only_pending: true)
      data = JSON.parse(response.content.first[:text])

      ids = data["messages"].map { |m| m["id"] }
      expect(ids).to include(pending.id)
      expect(ids).not_to include(delivered.id)
    end

    it "marks pending messages delivered when mark_delivered: true" do
      pending = send_msg

      response = described_class.call(slug: owner.slug, mark_delivered: true)
      data = JSON.parse(response.content.first[:text])

      expect(data["marked_delivered"]).to eq(1)
      expect(pending.reload).to be_delivered
    end

    it "returns error when note does not exist" do
      response = described_class.call(slug: "missing")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Recipient note not found")
    end

    it "honors limit" do
      5.times { send_msg }
      response = described_class.call(slug: owner.slug, limit: 2)
      data = JSON.parse(response.content.first[:text])

      expect(data["count"]).to eq(2)
    end

    it "marks delivered only the messages in the returned page, not all pending" do
      messages = Array.new(5) { send_msg }

      response = described_class.call(slug: owner.slug, limit: 2, mark_delivered: true)
      data = JSON.parse(response.content.first[:text])

      expect(data["count"]).to eq(2)
      expect(data["marked_delivered"]).to eq(2)

      returned_ids = data["messages"].map { |m| m["id"] }
      messages.each do |m|
        if returned_ids.include?(m.id)
          expect(m.reload).to be_delivered
        else
          expect(m.reload).not_to be_delivered
        end
      end
    end
  end
end
