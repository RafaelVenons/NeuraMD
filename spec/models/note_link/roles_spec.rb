require "rails_helper"

RSpec.describe NoteLink::Roles do
  describe "TOKEN_TO_SEMANTIC" do
    it "maps the hierarchical tokens to their semantic names" do
      expect(described_class::TOKEN_TO_SEMANTIC).to include(
        "f" => "target_is_parent",
        "c" => "target_is_child",
        "b" => "same_level",
        "n" => "next_in_sequence"
      )
    end

    it "maps the delegation tokens to their semantic names" do
      expect(described_class::TOKEN_TO_SEMANTIC).to include(
        "p" => "delegation_pending",
        "d" => "delegation_directive",
        "v" => "delegation_verify",
        "x" => "delegation_block"
      )
    end

    it "is frozen" do
      expect(described_class::TOKEN_TO_SEMANTIC).to be_frozen
    end
  end

  describe "SEMANTIC_NAMES" do
    it "lists every semantic value that hier_role may hold" do
      expect(described_class::SEMANTIC_NAMES).to contain_exactly(
        "target_is_parent",
        "target_is_child",
        "same_level",
        "next_in_sequence",
        "delegation_pending",
        "delegation_directive",
        "delegation_verify",
        "delegation_block"
      )
    end

    it "is frozen" do
      expect(described_class::SEMANTIC_NAMES).to be_frozen
    end
  end

  describe "SEMANTIC_TO_TOKEN" do
    it "is the inverse of TOKEN_TO_SEMANTIC" do
      expect(described_class::SEMANTIC_TO_TOKEN).to eq(described_class::TOKEN_TO_SEMANTIC.invert)
    end

    it "is frozen" do
      expect(described_class::SEMANTIC_TO_TOKEN).to be_frozen
    end
  end
end
