require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::BulkRemoveTagTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("bulk_remove_tag")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:tag) { create(:tag, name: "orfa") }
    let!(:keeper_tag) { create(:tag, name: "manter") }
    let!(:note_a) { create(:note, :with_head_revision, title: "A") }
    let!(:note_b) { create(:note, :with_head_revision, title: "B") }
    let!(:note_c) { create(:note, :with_head_revision, title: "C") }

    before do
      note_a.tags << tag
      note_a.tags << keeper_tag
      note_b.tags << tag
      note_c.tags << keeper_tag
    end

    it "removes the tag from every tagged note and reports the count" do
      response = described_class.call(tag: "orfa")
      data = JSON.parse(response.content.first[:text])

      expect(data["removed_from"]).to eq(2)
      expect(note_a.reload.tags.pluck(:name)).to contain_exactly("manter")
      expect(note_b.reload.tags.pluck(:name)).to be_empty
      expect(note_c.reload.tags.pluck(:name)).to contain_exactly("manter")
    end

    it "preserves the Tag row (only removes associations)" do
      described_class.call(tag: "orfa")
      expect(Tag.find_by(name: "orfa")).to be_present
    end

    it "also destroys the tag when delete_tag: true" do
      response = described_class.call(tag: "orfa", delete_tag: true)
      data = JSON.parse(response.content.first[:text])

      expect(data["tag_deleted"]).to be true
      expect(Tag.find_by(name: "orfa")).to be_nil
    end

    it "does not create checkpoints for affected notes" do
      revs_before = NoteRevision.count
      described_class.call(tag: "orfa")
      expect(NoteRevision.count).to eq(revs_before)
    end

    it "returns error when the tag does not exist" do
      response = described_class.call(tag: "nao-existe")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Tag not found")
    end

    it "reports zero when the tag exists but has no notes" do
      empty_tag = create(:tag, name: "vazia")
      response = described_class.call(tag: "vazia")
      data = JSON.parse(response.content.first[:text])

      expect(data["removed_from"]).to eq(0)
      expect(Tag.find_by(id: empty_tag.id)).to be_present
    end
  end
end
