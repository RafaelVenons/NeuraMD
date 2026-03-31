require "rails_helper"

RSpec.describe SlugRedirect, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:note) }
  end

  describe "validations" do
    it "requires slug to be present" do
      redirect = SlugRedirect.new(note: create(:note), slug: "")
      expect(redirect).not_to be_valid
      expect(redirect.errors[:slug]).to be_present
    end

    it "requires slug to be unique (case-insensitive)" do
      note = create(:note)
      SlugRedirect.create!(note: note, slug: "old-slug")
      duplicate = SlugRedirect.new(note: note, slug: "Old-Slug")
      expect(duplicate).not_to be_valid
    end
  end

  describe "dependent destroy" do
    it "is destroyed when note is destroyed" do
      note = create(:note)
      SlugRedirect.create!(note: note, slug: "old-slug")
      expect { note.destroy! }.to change(SlugRedirect, :count).by(-1)
    end
  end
end
