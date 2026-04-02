require "rails_helper"

RSpec.describe Blocks::SyncService do
  let(:note) { create(:note) }

  describe ".call" do
    it "creates blocks from content with markers" do
      content = "First paragraph. ^p1\n\n- A list item ^li1"
      described_class.call(note: note, content: content)

      expect(note.note_blocks.count).to eq(2)
      block = note.note_blocks.find_by(block_id: "p1")
      expect(block.content).to eq("First paragraph.")
      expect(block.block_type).to eq("paragraph")
    end

    it "replaces blocks when content changes" do
      described_class.call(note: note, content: "Old text. ^old1")
      described_class.call(note: note, content: "New text. ^new1")

      expect(note.note_blocks.count).to eq(1)
      expect(note.note_blocks.first.block_id).to eq("new1")
    end

    it "clears blocks when markers removed" do
      described_class.call(note: note, content: "Text with block. ^b1")
      described_class.call(note: note, content: "Text without block.")

      expect(note.note_blocks.count).to eq(0)
    end

    it "is idempotent" do
      content = "Some text. ^stable1"
      described_class.call(note: note, content: content)
      described_class.call(note: note, content: content)

      expect(note.note_blocks.count).to eq(1)
    end
  end
end
