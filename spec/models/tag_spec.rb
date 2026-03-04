require "rails_helper"

RSpec.describe Tag, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:note_tags).dependent(:destroy) }
    it { is_expected.to have_many(:notes).through(:note_tags) }
    it { is_expected.to have_many(:link_tags).dependent(:destroy) }
    it { is_expected.to have_many(:note_links).through(:link_tags) }
  end

  describe "validations" do
    subject { create(:tag) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    it { is_expected.to validate_inclusion_of(:tag_scope).in_array(Tag::TAG_SCOPES) }

    it "validates color_hex format" do
      tag = build(:tag, color_hex: "#gg1122")
      expect(tag).not_to be_valid
    end

    it "accepts blank color_hex" do
      tag = build(:tag, color_hex: "")
      expect(tag).to be_valid
    end
  end

  it "normalizes name to lowercase" do
    tag = create(:tag, name: "RubyOnRails")
    expect(tag.name).to eq("rubyonrails")
  end
end
