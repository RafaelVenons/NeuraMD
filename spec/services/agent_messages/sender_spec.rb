require "rails_helper"

RSpec.describe AgentMessages::Sender do
  let(:parent) { create(:note, title: "Parent") }
  let(:child)  { create(:note, title: "Child") }

  describe ".call" do
    it "persists a message" do
      msg = described_class.call(from: parent, to: child, content: "ping")

      expect(msg).to be_persisted
      expect(msg.from_note).to eq(parent)
      expect(msg.to_note).to eq(child)
      expect(msg.content).to eq("ping")
      expect(msg).not_to be_delivered
    end

    it "rejects blank endpoints" do
      expect {
        described_class.call(from: nil, to: child, content: "x")
      }.to raise_error(described_class::InvalidRecipient)
    end

    it "rejects self-addressed messages" do
      expect {
        described_class.call(from: parent, to: parent, content: "x")
      }.to raise_error(described_class::InvalidRecipient)
    end

    it "rejects empty content" do
      expect {
        described_class.call(from: parent, to: child, content: "   ")
      }.to raise_error(described_class::EmptyContent)
    end

    it "truncates oversized content" do
      big = "x" * (described_class::MAX_CONTENT_BYTES + 500)
      msg = described_class.call(from: parent, to: child, content: big)

      expect(msg.content.bytesize).to be <= described_class::MAX_CONTENT_BYTES + 64
      expect(msg.content).to include("[truncated — original")
    end
  end
end
