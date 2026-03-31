require "rails_helper"

RSpec.describe Properties::Validator do
  before do
    create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
    create(:property_definition, key: "priority", value_type: "number")
    create(:property_definition, key: "due_date", value_type: "date")
  end

  describe ".call" do
    it "returns valid for correct properties" do
      result = described_class.call({"status" => "draft", "priority" => 5})
      expect(result).to be_valid
      expect(result.errors).to be_empty
    end

    it "returns errors for invalid values" do
      result = described_class.call({"status" => "bad_value", "priority" => "not_a_number"})
      expect(result).not_to be_valid
      expect(result.errors).to have_key("status")
      expect(result.errors).to have_key("priority")
    end

    it "returns error for unknown keys" do
      result = described_class.call({"unknown_key" => "value"})
      expect(result).not_to be_valid
      expect(result.errors["unknown_key"]).to include("unknown property key")
    end

    it "returns valid for empty properties" do
      result = described_class.call({})
      expect(result).to be_valid
    end

    it "returns valid for nil properties" do
      result = described_class.call(nil)
      expect(result).to be_valid
    end

    it "ignores _errors key in properties_data" do
      result = described_class.call({"status" => "draft", "_errors" => {"old" => ["stale"]}})
      expect(result).to be_valid
    end

    it "validates mixed valid and invalid" do
      result = described_class.call({"status" => "draft", "due_date" => "not-a-date"})
      expect(result).not_to be_valid
      expect(result.errors).to have_key("due_date")
      expect(result.errors).not_to have_key("status")
    end
  end
end
