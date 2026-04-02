require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ReadNoteTool do
  let!(:note) { create(:note, :with_head_revision, title: "Nota de teste") }

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("read_note")
    expect(described_class.description_value).to be_present
  end

  it "reads a note by slug" do
    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["title"]).to eq("Nota de teste")
    expect(content["slug"]).to eq(note.slug)
    expect(content).to have_key("body")
    expect(content).to have_key("tags")
    expect(content).to have_key("links")
    expect(content).to have_key("created_at")
    expect(content).to have_key("updated_at")
  end

  it "includes tags in the response" do
    tag = create(:tag, name: "new-specs")
    note.tags << tag

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["tags"]).to include("new-specs")
  end

  it "includes outgoing links in the response" do
    target = create(:note, :with_head_revision, title: "Target note")
    revision = note.head_revision
    create(:note_link, src_note: note, dst_note: target, created_in_revision: revision)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["links"].length).to eq(1)
    expect(content["links"].first["target_title"]).to eq("Target note")
    expect(content["links"].first["direction"]).to eq("outgoing")
  end

  it "includes backlinks (incoming links) in the response" do
    source = create(:note, :with_head_revision, title: "Nota que referencia")
    create(:note_link, src_note: source, dst_note: note,
      hier_role: "target_is_child",
      created_in_revision: source.head_revision)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["backlinks"].length).to eq(1)
    expect(content["backlinks"].first["source_title"]).to eq("Nota que referencia")
    expect(content["backlinks"].first["role"]).to eq("target_is_child")
    expect(content["backlinks"].first["direction"]).to eq("incoming")
  end

  it "follows slug redirects" do
    create(:slug_redirect, note: note, slug: "old-slug")

    response = described_class.call(slug: "old-slug")
    content = JSON.parse(response.content.first[:text])
    expect(content["title"]).to eq("Nota de teste")
  end

  it "returns error for non-existent slug" do
    response = described_class.call(slug: "nao-existe")
    expect(response.error?).to be true
  end

  it "returns error for deleted note" do
    note.soft_delete!
    response = described_class.call(slug: note.slug)
    expect(response.error?).to be true
  end

  it "includes aliases in the response" do
    create(:note_alias, note: note, name: "Test Alias")
    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["aliases"]).to eq(["Test Alias"])
  end

  it "finds note by alias" do
    create(:note_alias, note: note, name: "My Alias")
    response = described_class.call(slug: "My Alias")
    content = JSON.parse(response.content.first[:text])
    expect(content["title"]).to eq("Nota de teste")
  end

  it "includes headings in the response" do
    create(:note_heading, note: note, level: 1, text: "Introduction", slug: "introduction", position: 0)
    create(:note_heading, note: note, level: 2, text: "Details", slug: "details", position: 1)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["headings"].length).to eq(2)
    expect(content["headings"].first).to eq({"text" => "Introduction", "slug" => "introduction", "level" => 1})
    expect(content["headings"].last).to eq({"text" => "Details", "slug" => "details", "level" => 2})
  end
end
