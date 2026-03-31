require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::SearchNotesTool do
  let!(:note1) { create(:note, :with_head_revision, title: "Arquitetura do sistema") }
  let!(:note2) { create(:note, :with_head_revision, title: "Busca textual avancada") }
  let!(:note3) { create(:note, :deleted, title: "Nota deletada") }

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("search_notes")
    expect(described_class.description_value).to be_present
  end

  it "searches notes by query" do
    response = described_class.call(query: "arquitetura")
    content = JSON.parse(response.content.first[:text])

    expect(content["notes"].length).to eq(1)
    expect(content["notes"].first["title"]).to eq("Arquitetura do sistema")
  end

  it "returns slug, title, excerpt, and tags" do
    tag = create(:tag, name: "plan")
    note1.tags << tag

    response = described_class.call(query: "arquitetura")
    note_data = JSON.parse(response.content.first[:text])["notes"].first

    expect(note_data).to have_key("slug")
    expect(note_data).to have_key("title")
    expect(note_data).to have_key("excerpt")
    expect(note_data).to have_key("tags")
    expect(note_data["tags"]).to include("plan")
  end

  it "excludes deleted notes" do
    response = described_class.call(query: "deletada")
    content = JSON.parse(response.content.first[:text])
    expect(content["notes"]).to be_empty
  end

  it "respects limit parameter" do
    3.times { |i| create(:note, :with_head_revision, title: "Resultado #{i}") }
    response = described_class.call(query: "resultado", limit: 2)
    content = JSON.parse(response.content.first[:text])
    expect(content["notes"].length).to eq(2)
  end

  it "returns empty results for blank query" do
    response = described_class.call(query: "")
    content = JSON.parse(response.content.first[:text])
    expect(content["notes"]).to be_an(Array)
  end

  context "with property_filters" do
    let(:user) { create(:user) }

    before do
      create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
      Properties::SetService.call(note: note1, changes: {"status" => "draft"}, author: user)
      Properties::SetService.call(note: note2, changes: {"status" => "published"}, author: user)
      note1.reload
      note2.reload
    end

    it "filters by property value" do
      response = described_class.call(query: "", property_filters: '{"status":"draft"}')
      content = JSON.parse(response.content.first[:text])
      titles = content["notes"].map { |n| n["title"] }

      expect(titles).to include("Arquitetura do sistema")
      expect(titles).not_to include("Busca textual avancada")
    end

    it "combines text search with property filter" do
      response = described_class.call(query: "arquitetura", property_filters: '{"status":"published"}')
      content = JSON.parse(response.content.first[:text])

      expect(content["notes"]).to be_empty
    end

    it "ignores invalid property_filters JSON" do
      response = described_class.call(query: "arquitetura", property_filters: "not-json")
      content = JSON.parse(response.content.first[:text])

      expect(content["notes"].length).to eq(1)
    end
  end
end
