require "rails_helper"

RSpec.describe NoteAlias, type: :model do
  subject(:note_alias) { build(:note_alias) }

  describe "associations" do
    it { is_expected.to belong_to(:note) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }

    it "enforces case-insensitive uniqueness" do
      create(:note_alias, name: "Cardio")
      duplicate = build(:note_alias, name: "cardio")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to be_present
    end

    it "allows different aliases on different notes" do
      create(:note_alias, name: "Alias A")
      other = build(:note_alias, name: "Alias B")
      expect(other).to be_valid
    end

    it "allows multiple aliases on the same note" do
      note = create(:note)
      create(:note_alias, note: note, name: "Alias A")
      second = build(:note_alias, note: note, name: "Alias B")
      expect(second).to be_valid
    end

    it "rejects alias that collides with existing note slug" do
      note = create(:note, title: "Cardiologia", slug: "cardiologia")
      other_note = create(:note)
      alias_record = build(:note_alias, note: other_note, name: "Cardiologia")
      expect(alias_record).not_to be_valid
      expect(alias_record.errors[:name]).to include("conflicts with an existing note slug")
    end

    it "allows alias that does not collide with any slug" do
      alias_record = build(:note_alias, name: "Something Unique XYZ")
      expect(alias_record).to be_valid
    end
  end

  describe "database constraints" do
    it "enforces unique lower(name) at database level" do
      create(:note_alias, name: "UniqueAlias")
      duplicate = build(:note_alias, name: "uniquealias")
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
