require "rails_helper"

RSpec.describe NoteBlock, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
  end

  describe "validations" do
    subject { build(:note_block) }

    it { is_expected.to validate_presence_of(:block_id) }
    it { is_expected.to validate_uniqueness_of(:block_id).scoped_to(:note_id) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:block_type) }
    it { is_expected.to validate_inclusion_of(:block_type).in_array(NoteBlock::BLOCK_TYPES) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }

    it "rejects block_id with invalid characters" do
      block = build(:note_block, block_id: "invalid id!")
      expect(block).not_to be_valid
    end

    it "accepts block_id with alphanumeric and hyphens" do
      block = build(:note_block, block_id: "my-block-1")
      expect(block).to be_valid
    end
  end

  describe "Note association" do
    it "note has_many note_blocks with dependent destroy" do
      note = create(:note)
      create(:note_block, note: note, position: 0, block_id: "a")
      create(:note_block, note: note, position: 1, block_id: "b")

      expect(note.note_blocks.count).to eq(2)
      note.destroy!
      expect(NoteBlock.count).to eq(0)
    end
  end
end
