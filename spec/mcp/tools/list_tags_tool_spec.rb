require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ListTagsTool do
  let!(:tag1) { create(:tag, name: "plan", color_hex: "#3B82F6") }
  let!(:tag2) { create(:tag, name: "new-specs", color_hex: "#10B981") }

  before do
    note = create(:note, :with_head_revision, title: "Test note")
    note.tags << tag1
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("list_tags")
    expect(described_class.description_value).to be_present
  end

  it "lists all tags ordered by name" do
    response = described_class.call
    content = JSON.parse(response.content.first[:text])

    expect(content["tags"].length).to eq(2)
    expect(content["tags"].first["name"]).to eq("new-specs")
    expect(content["tags"].last["name"]).to eq("plan")
  end

  it "includes notes_count" do
    response = described_class.call
    content = JSON.parse(response.content.first[:text])

    plan_tag = content["tags"].find { |t| t["name"] == "plan" }
    expect(plan_tag["notes_count"]).to eq(1)

    specs_tag = content["tags"].find { |t| t["name"] == "new-specs" }
    expect(specs_tag["notes_count"]).to eq(0)
  end

  it "includes color" do
    response = described_class.call
    content = JSON.parse(response.content.first[:text])

    plan_tag = content["tags"].find { |t| t["name"] == "plan" }
    expect(plan_tag["color"]).to eq("#3B82F6")
  end
end
