require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::CreateNoteTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("create_note")
    expect(described_class.description_value).to be_present
  end

  it "creates a note with title and content" do
    response = described_class.call(
      title: "Nova especificacao",
      content_markdown: "# Conteudo da spec\n\nDetalhes aqui."
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["created"]).to be true
    expect(content["title"]).to eq("Nova especificacao")
    expect(content["slug"]).to eq("nova-especificacao")

    note = Note.find_by(slug: "nova-especificacao")
    expect(note).to be_present
    expect(note.head_revision.content_markdown).to eq("# Conteudo da spec\n\nDetalhes aqui.")
  end

  it "applies tags when provided" do
    create(:tag, name: "shop")
    create(:tag, name: "shop-payments")

    response = described_class.call(
      title: "Payment gateway",
      content_markdown: "Gateway specs",
      tags: "shop,shop-payments"
    )
    content = JSON.parse(response.content.first[:text])

    note = Note.find_by(slug: content["slug"])
    expect(note.tags.pluck(:name)).to contain_exactly("shop", "shop-payments")
  end

  it "creates new tags that do not exist yet" do
    response = described_class.call(
      title: "Nota com tag nova",
      content_markdown: "Conteúdo",
      tags: "brand-new-tag"
    )
    content = JSON.parse(response.content.first[:text])

    expect(Tag.find_by(name: "brand-new-tag")).to be_present
    note = Note.find_by(slug: content["slug"])
    expect(note.tags.pluck(:name)).to include("brand-new-tag")
  end

  it "returns error for blank title" do
    response = described_class.call(title: "", content_markdown: "algo")
    expect(response.error?).to be true
  end

  it "returns error for blank content" do
    response = described_class.call(title: "Titulo", content_markdown: "")
    expect(response.error?).to be true
  end

  it "creates a checkpoint revision, not a draft" do
    described_class.call(title: "Check", content_markdown: "Body")
    note = Note.find_by(slug: "check")
    expect(note.head_revision.revision_kind).to eq("checkpoint")
  end

  it "creates NoteLinks from wikilinks in content" do
    target = create(:note, :with_head_revision, title: "Existing note")

    described_class.call(
      title: "Nota com link",
      content_markdown: "Referencia: [[Existing note|c:#{target.id}]]"
    )

    note = Note.find_by(slug: "nota-com-link")
    link = note.active_outgoing_links.find_by(dst_note_id: target.id)
    expect(link).to be_present
    expect(link.hier_role).to eq("target_is_child")
  end
end
