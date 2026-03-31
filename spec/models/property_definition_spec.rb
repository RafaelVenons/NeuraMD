require "rails_helper"

RSpec.describe PropertyDefinition, type: :model do
  describe "validations" do
    subject { build(:property_definition) }

    it "is valid with valid attributes" do
      expect(subject).to be_valid
    end

    it "requires a key" do
      subject.key = nil
      expect(subject).not_to be_valid
    end

    it "requires a unique key" do
      create(:property_definition, key: "status")
      dup = build(:property_definition, key: "status")
      expect(dup).not_to be_valid
    end

    it "enforces key format: lowercase alpha start" do
      subject.key = "Status"
      expect(subject).not_to be_valid
    end

    it "enforces key format: no spaces" do
      subject.key = "my key"
      expect(subject).not_to be_valid
    end

    it "enforces key format: no leading underscore" do
      subject.key = "_internal"
      expect(subject).not_to be_valid
    end

    it "allows underscores in key" do
      subject.key = "due_date"
      expect(subject).to be_valid
    end

    it "rejects reserved column names" do
      subject.key = "title"
      expect(subject).not_to be_valid
      expect(subject.errors[:key]).to include("is reserved")
    end

    it "requires a value_type" do
      subject.value_type = nil
      expect(subject).not_to be_valid
    end

    it "rejects unknown value_type" do
      subject.value_type = "color"
      expect(subject).not_to be_valid
    end

    PropertyDefinition::VALUE_TYPES.each do |vt|
      it "accepts value_type '#{vt}'" do
        subject.value_type = vt
        subject.config = (vt.include?("enum") ? {"options" => ["a"]} : {})
        expect(subject).to be_valid
      end
    end
  end

  describe "enum/multi_enum config validation" do
    it "requires options array for enum" do
      prop = build(:property_definition, value_type: "enum", config: {})
      expect(prop).not_to be_valid
      expect(prop.errors[:config].first).to include("options")
    end

    it "requires non-empty options for enum" do
      prop = build(:property_definition, value_type: "enum", config: {"options" => []})
      expect(prop).not_to be_valid
    end

    it "requires string options for multi_enum" do
      prop = build(:property_definition, value_type: "multi_enum", config: {"options" => [1, 2]})
      expect(prop).not_to be_valid
    end

    it "accepts valid enum config" do
      prop = build(:property_definition, :enum)
      expect(prop).to be_valid
    end
  end

  describe "scopes" do
    it ".active excludes archived definitions" do
      active = create(:property_definition, key: "active_prop")
      create(:property_definition, :archived, key: "archived_prop")
      expect(PropertyDefinition.active).to eq([active])
    end

    it ".system_keys returns only system definitions" do
      create(:property_definition, key: "user_prop")
      sys = create(:property_definition, :system, key: "sys_prop")
      expect(PropertyDefinition.system_keys).to eq([sys])
    end
  end

  describe ".registry" do
    it "returns a hash keyed by property key" do
      status = create(:property_definition, :enum, key: "status")
      create(:property_definition, :archived, key: "old_prop")
      registry = PropertyDefinition.registry
      expect(registry.keys).to eq(["status"])
      expect(registry["status"]).to eq(status)
    end
  end
end
