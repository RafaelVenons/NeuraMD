require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ImportMarkdownTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("import_markdown")
    expect(described_class.description_value).to be_present
  end

  describe "importing a simple markdown" do
    let(:markdown) do
      <<~MD
        # Plataforma de pagamentos

        Sistema de cobrança recorrente.

        ## Gateway

        Integração com Stripe e PagSeguro.

        ## Retry policy

        Tentativas com backoff exponencial.

        ### Circuit breaker

        Abre após 3 falhas consecutivas.
      MD
    end

    it "creates one note per heading" do
      response = described_class.call(
        markdown: markdown,
        base_tag: "shop",
        import_tag: "shop-import"
      )
      content = JSON.parse(response.content.first[:text])

      expect(content["created_count"]).to eq(4)
      expect(content["notes"].map { |n| n["title"] }).to contain_exactly(
        "Plataforma de pagamentos",
        "Gateway",
        "Retry policy",
        "Circuit breaker"
      )
    end

    it "does not inject redundant metadata in note body" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      Note.where(slug: "gateway").each do |note|
        body = note.head_revision.content_markdown
        expect(body).not_to include("Origem:")
        expect(body).not_to include("Profundidade:")
        expect(body).not_to include("Trilha:")
        expect(body).not_to include("Linha-guia:")
      end
    end

    it "keeps body content clean — heading + original text + child index" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      gateway = Note.joins(:tags).where(tags: {name: "shop-import"}).find_by(title: "Gateway")
      body = gateway.head_revision.content_markdown
      expect(body).to include("Integração com Stripe e PagSeguro.")
      expect(body).not_to include("Pai:")
      expect(body).not_to include("Temas:")
    end

    it "creates parent-child links via wikilinks in body" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      root = Note.joins(:tags).where(tags: {name: "shop-import"}).find_by(title: "Plataforma de pagamentos")
      children = root.active_outgoing_links.where(hier_role: "target_is_child")
      expect(children.count).to eq(2)
    end

    it "creates nested parent-child links" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      retry_note = Note.joins(:tags).where(tags: {name: "shop-import"}).find_by(title: "Retry policy")
      children = retry_note.active_outgoing_links.where(hier_role: "target_is_child")
      expect(children.count).to eq(1)
      expect(children.first.dst_note.title).to eq("Circuit breaker")
    end

    it "applies base_tag and import_tag to all notes" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      notes = Note.joins(:tags).where(tags: {name: "shop-import"})
      expect(notes.count).to eq(4)
      notes.each do |note|
        expect(note.tags.pluck(:name)).to include("shop")
      end
    end

    it "applies structural tags" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")

      root = Note.joins(:tags).where(tags: {name: "shop-import"}).find_by(title: "Plataforma de pagamentos")
      expect(root.tags.pluck(:name)).to include("shop-raiz")

      gateway = Note.joins(:tags).where(tags: {name: "shop-import"}).find_by(title: "Gateway")
      tag_names = gateway.tags.pluck(:name)
      expect(tag_names).to include("shop-h2")
    end
  end

  describe "reimport cleans previous batch" do
    let(:markdown) { "# Titulo\n\nConteudo." }

    it "deletes previous import before creating new notes" do
      described_class.call(markdown: markdown, base_tag: "shop", import_tag: "shop-import")
      expect(Note.joins(:tags).where(tags: {name: "shop-import"}).count).to eq(1)

      described_class.call(markdown: "# Novo titulo\n\nNovo.", base_tag: "shop", import_tag: "shop-import")
      imported = Note.joins(:tags).where(tags: {name: "shop-import"})
      expect(imported.count).to eq(1)
      expect(imported.first.title).to eq("Novo titulo")
    end
  end

  describe "extra tags" do
    it "applies additional tags from parameter" do
      described_class.call(
        markdown: "# Nota\n\nBody.",
        base_tag: "shop",
        import_tag: "shop-import",
        extra_tags: "iniciativa,estrutura-sistemica"
      )

      note = Note.joins(:tags).where(tags: {name: "shop-import"}).first
      expect(note.tags.pluck(:name)).to include("iniciativa", "estrutura-sistemica")
    end
  end
end
