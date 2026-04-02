require "rails_helper"

RSpec.describe NoteHeading, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
  end

  describe "validations" do
    subject { build(:note_heading) }

    it { is_expected.to validate_presence_of(:level) }
    it { is_expected.to validate_inclusion_of(:level).in_range(1..6) }
    it { is_expected.to validate_presence_of(:text) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_uniqueness_of(:slug).scoped_to(:note_id) }
  end

  describe "Note association" do
    it "note has_many note_headings with dependent destroy" do
      note = create(:note)
      create(:note_heading, note: note, position: 0, slug: "a")
      create(:note_heading, note: note, position: 1, slug: "b")

      expect(note.note_headings.count).to eq(2)
      note.destroy!
      expect(NoteHeading.count).to eq(0)
    end
  end
end
