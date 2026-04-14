require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::PatchNoteTool do
  let(:body) do
    <<~MD
      # Introdução

      Texto de abertura.

      ## Tarefas

      - item 1
      - item 2

      ## Referências

      - ref 1
    MD
  end

  let!(:note) do
    n = create(:note, title: "Nota")
    Notes::CheckpointService.call(note: n, content: body, author: nil, accepted_ai_request: nil)
    n.reload
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("patch_note")
    expect(described_class.description_value).to be_present
  end

  it "appends content to a heading section" do
    response = described_class.call(
      slug: note.slug,
      heading: "Tarefas",
      operation: "append",
      content: "- item 3"
    )
    content = JSON.parse(response.content.first[:text])
    expect(content["patched"]).to be true

    body = note.reload.head_revision.content_markdown
    tarefas = body[/## Tarefas.*?(?=## Referências)/m]
    expect(tarefas).to include("- item 1")
    expect(tarefas).to include("- item 2")
    expect(tarefas).to include("- item 3")
    expect(body.index("- item 3")).to be < body.index("## Referências")
  end

  it "prepends content right after the heading line" do
    response = described_class.call(
      slug: note.slug,
      heading: "Tarefas",
      operation: "prepend",
      content: "- item 0"
    )
    expect(JSON.parse(response.content.first[:text])["patched"]).to be true

    body = note.reload.head_revision.content_markdown
    expect(body).to match(/## Tarefas\n\n- item 0\n/)
  end

  it "replaces the section body (keeps the heading)" do
    response = described_class.call(
      slug: note.slug,
      heading: "Tarefas",
      operation: "replace_section",
      content: "nova lista"
    )
    expect(JSON.parse(response.content.first[:text])["patched"]).to be true

    body = note.reload.head_revision.content_markdown
    expect(body).to include("## Tarefas\n\nnova lista\n")
    expect(body).not_to include("- item 1")
    expect(body).to include("## Referências")
  end

  it "treats a heading's section as extending through its subsections (markdown semantics)" do
    # Introdução is level 1; Tarefas and Referências are level 2 nested under it.
    # Appending to Introdução therefore inserts at EOF, after all subsections.
    response = described_class.call(
      slug: note.slug,
      heading: "Introdução",
      operation: "append",
      content: "parágrafo extra."
    )
    expect(JSON.parse(response.content.first[:text])["patched"]).to be true

    body = note.reload.head_revision.content_markdown
    expect(body.index("parágrafo extra.")).to be > body.index("## Referências")
  end

  it "creates a new checkpoint revision" do
    expect {
      described_class.call(slug: note.slug, heading: "Tarefas", operation: "append", content: "- x")
    }.to change { note.note_revisions.count }.by(1)
  end

  it "returns error with available headings when heading not found" do
    response = described_class.call(
      slug: note.slug,
      heading: "Inexistente",
      operation: "append",
      content: "x"
    )
    expect(response.error?).to be true
    text = response.content.first[:text]
    expect(text).to include("Heading not found")
    expect(text).to include("Tarefas")
    expect(text).to include("Referências")
  end

  it "returns error when note not found" do
    response = described_class.call(
      slug: "nope",
      heading: "Tarefas",
      operation: "append",
      content: "x"
    )
    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("Note not found")
  end

  it "returns error for unknown operation" do
    response = described_class.call(
      slug: note.slug,
      heading: "Tarefas",
      operation: "wreck",
      content: "x"
    )
    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("operation")
  end

  it "matches heading case-insensitively with whitespace tolerance" do
    response = described_class.call(
      slug: note.slug,
      heading: "  tarefas  ",
      operation: "append",
      content: "- item 3"
    )
    expect(JSON.parse(response.content.first[:text])["patched"]).to be true
  end

  it "follows slug redirects" do
    old_slug = note.slug
    Notes::RenameService.call(note: note, new_title: "Nota renomeada")

    response = described_class.call(
      slug: old_slug,
      heading: "Tarefas",
      operation: "append",
      content: "- via redirect"
    )
    expect(JSON.parse(response.content.first[:text])["patched"]).to be true
  end
end
