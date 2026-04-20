require "rails_helper"

RSpec.describe ExtensionManifest do
  describe ".all" do
    it "returns all extension points" do
      expect(described_class.all.keys).to contain_exactly(
        :search_operators, :renderers, :property_types,
        :domain_events, :display_types
      )
    end
  end

  describe ".extensible" do
    it "returns only non-sealed extension points" do
      extensible = described_class.extensible
      extensible.each_value do |ep|
        expect(ep[:sealed]).to be false
      end
    end

    it "includes search_operators and renderers" do
      expect(described_class.extensible.keys).to include(:search_operators, :renderers)
    end
  end

  describe ".sealed" do
    it "returns only sealed extension points" do
      sealed = described_class.sealed
      sealed.each_value do |ep|
        expect(ep[:sealed]).to be true
      end
    end

    it "includes property_types, display_types" do
      expect(described_class.sealed.keys).to include(:property_types, :display_types)
    end
  end

  describe ".find" do
    it "returns the extension point by name" do
      ep = described_class.find(:search_operators)
      expect(ep[:registry]).to eq("Search::Dsl::OperatorRegistry")
      expect(ep[:contract]).to include(:apply)
    end

    it "raises KeyError for unknown name" do
      expect {
        described_class.find(:nonexistent)
      }.to raise_error(KeyError, /nonexistent/)
    end
  end

  describe "registries referenced in manifest exist" do
    it "Search::Dsl::OperatorRegistry is defined" do
      expect(defined?(Search::Dsl::OperatorRegistry)).to be_truthy
    end

    it "Properties::TypeRegistry is defined" do
      expect(defined?(Properties::TypeRegistry)).to be_truthy
    end

    it "DOMAIN_EVENT_CATALOG is defined" do
      expect(defined?(DOMAIN_EVENT_CATALOG)).to be_truthy
    end

    it "NoteView::DISPLAY_TYPES is defined" do
      expect(defined?(NoteView::DISPLAY_TYPES)).to be_truthy
    end
  end

  describe "SEALED_BOUNDARIES" do
    it "lists non-extensible system areas" do
      expect(described_class::SEALED_BOUNDARIES).to include("authentication", "database_schema")
    end
  end
end
