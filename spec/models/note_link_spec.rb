require "rails_helper"

RSpec.describe NoteLink, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:src_note).class_name("Note") }
    it { is_expected.to belong_to(:dst_note).class_name("Note") }
    it { is_expected.to belong_to(:created_in_revision).class_name("NoteRevision") }
    it { is_expected.to have_many(:link_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:link_tags) }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:hier_role).in_array(NoteLink::HIER_ROLES).allow_nil }

    it "prevents self-links" do
      note = create(:note)
      revision = create(:note_revision, note: note)
      link = build(:note_link, src_note: note, dst_note: note, created_in_revision: revision)
      expect(link).not_to be_valid
      expect(link.errors[:dst_note_id]).to be_present
    end

    it "prevents duplicate links between same pair" do
      src = create(:note)
      dst = create(:note)
      revision = create(:note_revision, note: src)
      create(:note_link, src_note: src, dst_note: dst, created_in_revision: revision)
      duplicate = build(:note_link, src_note: src, dst_note: dst, created_in_revision: revision)
      expect(duplicate).not_to be_valid
    end
  end
end
