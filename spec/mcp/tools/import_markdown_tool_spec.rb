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

  describe "sequential navigation links" do
    let(:markdown) do
      <<~MD
        # Book

        Intro.

        ## Chapter 1

        Content one.

        ## Chapter 2

        Content two.

        ## Chapter 3

        Content three.
      MD
    end

    it "adds prev/next links between sibling notes" do
      described_class.call(markdown: markdown, base_tag: "nav", import_tag: "nav-import")

      ch1 = Note.joins(:tags).where(tags: {name: "nav-import"}).find_by(title: "Chapter 1")
      ch2 = Note.joins(:tags).where(tags: {name: "nav-import"}).find_by(title: "Chapter 2")
      ch3 = Note.joins(:tags).where(tags: {name: "nav-import"}).find_by(title: "Chapter 3")

      body1 = ch1.head_revision.content_markdown
      expect(body1).to include("Proximo: [[Chapter 2|n:#{ch2.id}]]")
      expect(body1).not_to include("Anterior:")

      body2 = ch2.head_revision.content_markdown
      expect(body2).to include("Anterior: [[Chapter 1|n:#{ch1.id}]]")
      expect(body2).to include("Proximo: [[Chapter 3|n:#{ch3.id}]]")

      body3 = ch3.head_revision.content_markdown
      expect(body3).to include("Anterior: [[Chapter 2|n:#{ch2.id}]]")
      expect(body3).not_to include("Proximo:")
    end

    it "does not add nav links to single-child sections" do
      single_child_md = "# Root\n\nIntro.\n\n## Only Child\n\nContent."
      described_class.call(markdown: single_child_md, base_tag: "nav", import_tag: "nav-import")

      child = Note.joins(:tags).where(tags: {name: "nav-import"}).find_by(title: "Only Child")
      body = child.head_revision.content_markdown
      expect(body).not_to include("Anterior:")
      expect(body).not_to include("Proximo:")
    end

    it "does not add nav links to root note" do
      described_class.call(markdown: markdown, base_tag: "nav", import_tag: "nav-import")

      root = Note.joins(:tags).where(tags: {name: "nav-import"}).find_by(title: "Book")
      body = root.head_revision.content_markdown
      expect(body).not_to include("Anterior:")
      expect(body).not_to include("Proximo:")
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

  describe "chapter grouping" do
    it "groups children into Parte N when >20 children" do
      chapters = (1..25).map { |i| "## Chapter #{i}\n\nContent for chapter #{i}." }.join("\n\n")
      md = "# Big Book\n\nIntro.\n\n#{chapters}"

      response = described_class.call(markdown: md, base_tag: "group", import_tag: "group-import")
      result = JSON.parse(response.content.first[:text])
      titles = result["notes"].map { |n| n["title"] }

      expect(titles).to include("Parte 1", "Parte 2", "Parte 3")
      expect(titles).not_to include("Big Book" => have_attributes(size: 25))

      root = Note.joins(:tags).where(tags: {name: "group-import"}).find_by(title: "Big Book")
      root_children = root.active_outgoing_links.where(hier_role: "target_is_child")
      expect(root_children.count).to eq(3) # 3 parts instead of 25 chapters
    end

    it "does not group when <=20 children" do
      chapters = (1..5).map { |i| "## Ch #{i}\n\nContent #{i}." }.join("\n\n")
      md = "# Small Book\n\nIntro.\n\n#{chapters}"

      response = described_class.call(markdown: md, base_tag: "group", import_tag: "group-import")
      result = JSON.parse(response.content.first[:text])
      titles = result["notes"].map { |n| n["title"] }

      expect(titles).not_to include(match(/Parte/))
    end
  end

  describe "split_level" do
    let(:book_markdown) do
      <<~MD
        # My Book

        Introduction text.

        ## Chapter 1

        Chapter 1 content.

        ### Section 1.1

        Section 1.1 content.

        #### Subsection 1.1.1

        Deep content.

        ## Chapter 2

        Chapter 2 content.

        ### Section 2.1

        Section 2.1 content.
      MD
    end

    context "when split_level is nil (default, backward-compat)" do
      it "fragments at every heading" do
        response = described_class.call(
          markdown: book_markdown, base_tag: "book", import_tag: "book-import"
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["created_count"]).to eq(6)
      end
    end

    context "when split_level is 0 (no fragmentation)" do
      it "creates a single note with all content inline" do
        response = described_class.call(
          markdown: book_markdown, base_tag: "book", import_tag: "book-import", split_level: 0
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["created_count"]).to eq(1)

        note = Note.joins(:tags).where(tags: {name: "book-import"}).first
        body = note.head_revision.content_markdown
        expect(body).to include("## Chapter 1")
        expect(body).to include("### Section 1.1")
        expect(body).to include("Deep content.")
      end
    end

    context "when split_level is 2 (cut at H1+H2)" do
      it "creates notes for H1 and H2 only, keeping H3+ inline" do
        response = described_class.call(
          markdown: book_markdown, base_tag: "book", import_tag: "book-import", split_level: 2
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["created_count"]).to eq(3)
        expect(result["notes"].map { |n| n["title"] }).to contain_exactly(
          "My Book", "Chapter 1", "Chapter 2"
        )

        ch1 = Note.joins(:tags).where(tags: {name: "book-import"}).find_by(title: "Chapter 1")
        body = ch1.head_revision.content_markdown
        expect(body).to include("### Section 1.1")
        expect(body).to include("Section 1.1 content.")
        expect(body).to include("#### Subsection 1.1.1")
        expect(body).to include("Deep content.")
      end
    end

    context "when split_level is 1 (cut at H1 only)" do
      it "creates only H1 notes with everything else inline" do
        response = described_class.call(
          markdown: book_markdown, base_tag: "book", import_tag: "book-import", split_level: 1
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["created_count"]).to eq(1)

        note = Note.joins(:tags).where(tags: {name: "book-import"}).first
        body = note.head_revision.content_markdown
        expect(body).to include("## Chapter 1")
        expect(body).to include("## Chapter 2")
      end
    end

    context "when split_level is -1 (auto-detect)" do
      it "detects single H1 + multiple H2 as split_level 2" do
        response = described_class.call(
          markdown: book_markdown, base_tag: "book", import_tag: "book-import", split_level: -1
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["split_level_used"]).to eq(2)
        expect(result["created_count"]).to eq(3)
      end

      it "detects multiple H1 as split_level 1" do
        multi_h1 = <<~MD
          # Part One

          Content one.

          # Part Two

          Content two.
        MD

        response = described_class.call(
          markdown: multi_h1, base_tag: "book", import_tag: "book-import", split_level: -1
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["split_level_used"]).to eq(1)
        expect(result["created_count"]).to eq(2)
      end

      it "does not fragment ambiguous content" do
        simple = <<~MD
          # Single Title

          Just some text without sub-headings.
        MD

        response = described_class.call(
          markdown: simple, base_tag: "book", import_tag: "book-import", split_level: -1
        )
        result = JSON.parse(response.content.first[:text])
        expect(result["split_level_used"]).to eq(0)
        expect(result["created_count"]).to eq(1)
      end
    end
  end
end
