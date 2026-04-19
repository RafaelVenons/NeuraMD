require "rails_helper"

RSpec.describe AgentMessage do
  let(:parent) { create(:note, title: "Parent") }
  let(:child)  { create(:note, title: "Child") }

  describe "validations" do
    it "requires content" do
      msg = described_class.new(from_note: parent, to_note: child, content: "")
      expect(msg).not_to be_valid
      expect(msg.errors[:content]).to be_present
    end

    it "rejects messages from a note to itself" do
      msg = described_class.new(from_note: parent, to_note: parent, content: "hi")
      expect(msg).not_to be_valid
      expect(msg.errors[:to_note_id]).to include("cannot equal from_note_id")
    end

    it "requires both endpoints" do
      expect(described_class.new(to_note: child, content: "hi")).not_to be_valid
      expect(described_class.new(from_note: parent, content: "hi")).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:pending_msg) { described_class.create!(from_note: parent, to_note: child, content: "wait") }
    let!(:delivered_msg) do
      described_class.create!(
        from_note: parent, to_note: child, content: "ack", delivered_at: 1.minute.ago
      )
    end

    it "separates pending from delivered" do
      expect(described_class.pending).to contain_exactly(pending_msg)
      expect(described_class.delivered).to contain_exactly(delivered_msg)
    end

    it "inbox scopes by the recipient note" do
      expect(described_class.inbox(child)).to contain_exactly(pending_msg, delivered_msg)
      expect(described_class.inbox(parent)).to be_empty
    end

    it "outbox scopes by the sender note" do
      expect(described_class.outbox(parent)).to contain_exactly(pending_msg, delivered_msg)
      expect(described_class.outbox(child)).to be_empty
    end
  end

  describe "#mark_delivered!" do
    it "flips delivered_at and is idempotent" do
      msg = described_class.create!(from_note: parent, to_note: child, content: "hi")
      expect(msg).not_to be_delivered

      msg.mark_delivered!
      expect(msg.reload).to be_delivered

      first_stamp = msg.delivered_at
      msg.mark_delivered!
      expect(msg.reload.delivered_at.to_i).to eq(first_stamp.to_i)
    end
  end

  describe "Note associations" do
    it "exposes incoming and outgoing messages on Note" do
      msg = described_class.create!(from_note: parent, to_note: child, content: "hi")
      expect(parent.outgoing_agent_messages).to contain_exactly(msg)
      expect(child.incoming_agent_messages).to contain_exactly(msg)
    end

    it "deletes its agent messages when a note is destroyed" do
      described_class.create!(from_note: parent, to_note: child, content: "hi")
      expect { child.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
