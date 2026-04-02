require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::UpdateNoteTool do
  let!(:note) { create(:note, :with_head_revision, title: "Nota original") }

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("update_note")
    expect(described_class.description_value).to be_present
  end

  it "updates content via checkpoint" do
    response = described_class.call(
      slug: note.slug,
      content_markdown: "# Conteúdo atualizado"
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(note.reload.head_revision.content_markdown).to eq("# Conteúdo atualizado")
  end

  it "renames via RenameService when title changes" do
    old_slug = note.slug
    response = described_class.call(
      slug: note.slug,
      title: "Titulo renomeado"
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(content["slug"]).to eq("titulo-renomeado")
    expect(content["title"]).to eq("Titulo renomeado")
    expect(SlugRedirect.find_by(slug: old_slug)).to be_present
  end

  it "updates both title and content in one call" do
    response = described_class.call(
      slug: note.slug,
      title: "Novo titulo",
      content_markdown: "Novo conteúdo"
    )
    content = JSON.parse(response.content.first[:text])

    note.reload
    expect(content["updated"]).to be true
    expect(note.title).to eq("Novo titulo")
    expect(note.head_revision.content_markdown).to eq("Novo conteúdo")
  end

  it "adds tags" do
    create(:tag, name: "queue")
    response = described_class.call(
      slug: note.slug,
      add_tags: "queue"
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(note.reload.tags.pluck(:name)).to include("queue")
  end

  it "removes tags" do
    tag = create(:tag, name: "old-tag")
    note.tags << tag

    response = described_class.call(
      slug: note.slug,
      remove_tags: "old-tag"
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(note.reload.tags.pluck(:name)).not_to include("old-tag")
  end

  it "creates tags that do not exist when adding" do
    described_class.call(slug: note.slug, add_tags: "new-tag-here")
    expect(Tag.find_by(name: "new-tag-here")).to be_present
    expect(note.reload.tags.pluck(:name)).to include("new-tag-here")
  end

  it "follows slug redirects" do
    create(:slug_redirect, note: note, slug: "old-slug")
    response = described_class.call(
      slug: "old-slug",
      content_markdown: "Via redirect"
    )
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(note.reload.head_revision.content_markdown).to eq("Via redirect")
  end

  it "returns error for non-existent slug" do
    response = described_class.call(slug: "nao-existe", content_markdown: "x")
    expect(response.error?).to be true
  end

  it "returns error when nothing to update" do
    response = described_class.call(slug: note.slug)
    expect(response.error?).to be true
  end

  it "appends wikilinks to existing content and creates NoteLinks" do
    target = create(:note, :with_head_revision, title: "Target")
    original_body = note.head_revision.content_markdown

    response = described_class.call(
      slug: note.slug,
      append_links: "Target|b:#{target.id}"
    )
    content = JSON.parse(response.content.first[:text])
    expect(content["updated"]).to be true

    note.reload
    expect(note.head_revision.content_markdown).to include("[[Target|b:#{target.id}]]")
    expect(note.head_revision.content_markdown).to start_with(original_body.rstrip)

    link = note.active_outgoing_links.find_by(dst_note_id: target.id)
    expect(link).to be_present
    expect(link.hier_role).to eq("same_level")
  end

  it "appends multiple wikilinks at once" do
    t1 = create(:note, :with_head_revision, title: "Child 1")
    t2 = create(:note, :with_head_revision, title: "Child 2")

    described_class.call(
      slug: note.slug,
      append_links: "Child 1|c:#{t1.id},Child 2|c:#{t2.id}"
    )

    note.reload
    expect(note.head_revision.content_markdown).to include("[[Child 1|c:#{t1.id}]]")
    expect(note.head_revision.content_markdown).to include("[[Child 2|c:#{t2.id}]]")
    expect(note.active_outgoing_links.count).to eq(2)
  end

  it "appends wikilinks even when content_markdown is also provided" do
    target = create(:note, :with_head_revision, title: "Lateral")

    described_class.call(
      slug: note.slug,
      content_markdown: "# New content",
      append_links: "Lateral|b:#{target.id}"
    )

    note.reload
    expect(note.head_revision.content_markdown).to include("# New content")
    expect(note.head_revision.content_markdown).to include("[[Lateral|b:#{target.id}]]")

    link = note.active_outgoing_links.find_by(dst_note_id: target.id)
    expect(link).to be_present
    expect(link.hier_role).to eq("same_level")
  end

  it "sets aliases on a note" do
    response = described_class.call(slug: note.slug, set_aliases: '["Cardio", "Heart"]')
    content = JSON.parse(response.content.first[:text])

    expect(content["aliases"]).to contain_exactly("Cardio", "Heart")
    expect(note.note_aliases.reload.pluck(:name)).to contain_exactly("Cardio", "Heart")
  end

  it "finds note by alias for update" do
    create(:note_alias, note: note, name: "Original Alias")
    response = described_class.call(slug: "Original Alias", add_tags: "test-tag")
    content = JSON.parse(response.content.first[:text])

    expect(content["updated"]).to be true
    expect(content["tags"]).to include("test-tag")
  end
end
