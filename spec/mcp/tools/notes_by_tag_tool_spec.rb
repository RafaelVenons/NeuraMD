require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::NotesByTagTool do
  let!(:tag) { create(:tag, name: "queue") }
  let!(:note1) { create(:note, :with_head_revision, title: "Fila de processamento") }
  let!(:note2) { create(:note, :with_head_revision, title: "Retry e cancelamento") }
  let!(:note3) { create(:note, :with_head_revision, title: "Nota sem tag") }

  before do
    note1.tags << tag
    note2.tags << tag
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("notes_by_tag")
    expect(described_class.description_value).to be_present
  end

  it "returns notes with the specified tag" do
    response = described_class.call(tag: "queue")
    content = JSON.parse(response.content.first[:text])

    expect(content["notes"].length).to eq(2)
    titles = content["notes"].map { |n| n["title"] }
    expect(titles).to include("Fila de processamento", "Retry e cancelamento")
  end

  it "does not include notes without the tag" do
    response = described_class.call(tag: "queue")
    content = JSON.parse(response.content.first[:text])

    titles = content["notes"].map { |n| n["title"] }
    expect(titles).not_to include("Nota sem tag")
  end

  it "excludes deleted notes" do
    note1.soft_delete!
    response = described_class.call(tag: "queue")
    content = JSON.parse(response.content.first[:text])
    expect(content["notes"].length).to eq(1)
  end

  it "respects limit parameter" do
    response = described_class.call(tag: "queue", limit: 1)
    content = JSON.parse(response.content.first[:text])
    expect(content["notes"].length).to eq(1)
  end

  it "returns error for non-existent tag" do
    response = described_class.call(tag: "nao-existe")
    expect(response.error?).to be true
  end

  it "excludes notes with any tag listed in exclude_tags" do
    estrutura = create(:tag, name: "queue-estrutura")
    note1.tags << estrutura

    response = described_class.call(tag: "queue", exclude_tags: "queue-estrutura")
    content = JSON.parse(response.content.first[:text])

    slugs = content["notes"].map { |n| n["slug"] }
    expect(slugs).not_to include(note1.slug)
    expect(slugs).to include(note2.slug)
  end

  it "supports multiple comma-separated exclude_tags" do
    estrutura = create(:tag, name: "queue-estrutura")
    merged = create(:tag, name: "queue-merged")
    note1.tags << estrutura
    note2.tags << merged

    response = described_class.call(tag: "queue", exclude_tags: "queue-estrutura,queue-merged")
    content = JSON.parse(response.content.first[:text])

    expect(content["notes"]).to be_empty
  end

  it "ignores non-existent exclude_tags silently" do
    response = described_class.call(tag: "queue", exclude_tags: "no-such-tag")
    content = JSON.parse(response.content.first[:text])

    expect(content["notes"].length).to eq(2)
  end

  it "returns slug, title, and excerpt" do
    response = described_class.call(tag: "queue")
    note_data = JSON.parse(response.content.first[:text])["notes"].first

    expect(note_data).to have_key("slug")
    expect(note_data).to have_key("title")
    expect(note_data).to have_key("excerpt")
  end
end
