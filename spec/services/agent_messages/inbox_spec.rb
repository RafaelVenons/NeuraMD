require "rails_helper"

RSpec.describe AgentMessages::Inbox do
  let(:parent)  { create(:note, title: "Parent") }
  let(:child)   { create(:note, title: "Child") }
  let(:sibling) { create(:note, title: "Sibling") }

  def msg(to:, from: parent, delivered: false)
    attrs = { from_note: from, to_note: to, content: "hi" }
    attrs[:delivered_at] = 1.minute.ago if delivered
    AgentMessage.create!(attrs)
  end

  describe ".for" do
    it "returns inbox messages newest first, scoped to the recipient" do
      older = msg(to: child)
      older.update!(created_at: 2.hours.ago)
      newer = msg(to: child)
      msg(to: parent, from: sibling)

      expect(described_class.for(child).to_a).to eq([newer, older])
    end

    it "filters to pending when only_pending is set" do
      delivered = msg(to: child, delivered: true)
      pending   = msg(to: child)

      result = described_class.for(child, only_pending: true).to_a
      expect(result).to contain_exactly(pending)
      expect(result).not_to include(delivered)
    end

    it "clamps the limit between 1 and 200" do
      10.times { msg(to: child) }

      expect(described_class.for(child, limit: 0).to_a.size).to eq(1)
      expect(described_class.for(child, limit: 10_000).to_a.size).to eq(10)
    end
  end

  describe ".mark_all_delivered!" do
    it "flips pending messages for the note and leaves others untouched" do
      pending_for_child   = msg(to: child)
      delivered_for_child = msg(to: child, delivered: true)
      pending_for_parent  = msg(to: parent, from: child)

      described_class.mark_all_delivered!(child)

      expect(pending_for_child.reload).to be_delivered
      expect(pending_for_parent.reload).not_to be_delivered
      expect(delivered_for_child.reload).to be_delivered
    end
  end

  describe ".mark_delivered!" do
    it "flips only the listed message ids scoped to the note" do
      keep    = msg(to: child)
      flip    = msg(to: child)
      sibling = msg(to: parent, from: child)

      count = described_class.mark_delivered!(child, ids: [flip.id, sibling.id])

      expect(count).to eq(1)
      expect(flip.reload).to be_delivered
      expect(keep.reload).not_to be_delivered
      expect(sibling.reload).not_to be_delivered
    end

    it "returns 0 and no-ops when ids are blank" do
      pending = msg(to: child)

      expect(described_class.mark_delivered!(child, ids: [])).to eq(0)
      expect(described_class.mark_delivered!(child, ids: nil)).to eq(0)
      expect(pending.reload).not_to be_delivered
    end
  end
end
