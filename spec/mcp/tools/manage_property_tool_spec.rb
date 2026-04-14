require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ManagePropertyTool do
  let!(:note) { create(:note, :with_head_revision, title: "Nota") }

  before do
    create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
    create(:property_definition, key: "priority", value_type: "number", config: {})
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("manage_property")
    expect(described_class.description_value).to be_present
  end

  describe "get" do
    it "returns the current value when set" do
      Properties::SetService.call(note: note, changes: {"status" => "draft"})
      response = described_class.call(slug: note.slug, operation: "get", key: "status")
      data = JSON.parse(response.content.first[:text])

      expect(data["value"]).to eq("draft")
      expect(data["present"]).to be true
    end

    it "returns present: false when not set" do
      response = described_class.call(slug: note.slug, operation: "get", key: "status")
      data = JSON.parse(response.content.first[:text])

      expect(data["value"]).to be_nil
      expect(data["present"]).to be false
    end
  end

  describe "set" do
    it "sets a string value (JSON-quoted)" do
      response = described_class.call(slug: note.slug, operation: "set", key: "status", value: '"draft"')
      data = JSON.parse(response.content.first[:text])

      expect(data["value"]).to eq("draft")
      expect(note.reload.current_properties["status"]).to eq("draft")
    end

    it "sets an integer value" do
      response = described_class.call(slug: note.slug, operation: "set", key: "priority", value: "3")
      data = JSON.parse(response.content.first[:text])

      expect(data["value"]).to eq(3)
    end

    it "accepts bare strings when not valid JSON" do
      response = described_class.call(slug: note.slug, operation: "set", key: "status", value: "draft")
      data = JSON.parse(response.content.first[:text])
      expect(data["value"]).to eq("draft")
    end

    it "creates a checkpoint revision" do
      expect {
        described_class.call(slug: note.slug, operation: "set", key: "status", value: '"draft"')
      }.to change { note.note_revisions.count }.by(1)
    end

    it "returns error for unknown key" do
      response = described_class.call(slug: note.slug, operation: "set", key: "nonexistent", value: '"x"')
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Unknown property key")
    end

    it "returns error for invalid value (fails validation)" do
      response = described_class.call(slug: note.slug, operation: "set", key: "status", value: '"bogus"')
      expect(response.error?).to be true
    end

    it "returns error when value missing" do
      response = described_class.call(slug: note.slug, operation: "set", key: "status")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("value is required")
    end
  end

  describe "delete" do
    before { Properties::SetService.call(note: note, changes: {"status" => "draft"}) }

    it "removes the property" do
      response = described_class.call(slug: note.slug, operation: "delete", key: "status")
      data = JSON.parse(response.content.first[:text])

      expect(data["present"]).to be false
      expect(note.reload.current_properties).not_to have_key("status")
    end

    it "creates a checkpoint revision" do
      expect {
        described_class.call(slug: note.slug, operation: "delete", key: "status")
      }.to change { note.note_revisions.count }.by(1)
    end
  end

  it "returns error for unknown operation" do
    response = described_class.call(slug: note.slug, operation: "wreck", key: "status")
    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("Invalid operation")
  end

  it "returns error when note not found" do
    response = described_class.call(slug: "nope", operation: "get", key: "status")
    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("Note not found")
  end

  it "follows slug redirects" do
    old_slug = note.slug
    Notes::RenameService.call(note: note, new_title: "Nota renomeada")
    response = described_class.call(slug: old_slug, operation: "set", key: "status", value: '"draft"')
    expect(JSON.parse(response.content.first[:text])["value"]).to eq("draft")
  end
end
