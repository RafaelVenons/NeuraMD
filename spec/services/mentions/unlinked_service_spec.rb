require "rails_helper"

RSpec.describe Mentions::UnlinkedService do
  describe ".call" do
    let!(:target) { create(:note, :with_head_revision, title: "Neurociência") }

    def create_note_with_content(title:, content:)
      note = create(:note, title: title)
      rev = create(:note_revision, note: note, content_markdown: content)
      note.update_columns(head_revision_id: rev.id)
      note
    end

    it "finds mention by exact title in content" do
      create_note_with_content(title: "Artigo", content: "Este artigo fala de Neurociência em detalhes.")

      result = described_class.call(note: target)
      expect(result.mentions.size).to eq(1)
      expect(result.mentions.first.source_note.title).to eq("Artigo")
      expect(result.mentions.first.matched_term).to eq("Neurociência")
    end

    it "finds mention by alias" do
      create(:note_alias, note: target, name: "neuro")
      create_note_with_content(title: "Artigo", content: "O campo de neuro é vasto.")

      result = described_class.call(note: target)
      expect(result.mentions.size).to eq(1)
      expect(result.mentions.first.matched_term).to eq("neuro")
    end

    it "matches case-insensitively" do
      create_note_with_content(title: "Artigo", content: "Estudamos neurociência avançada.")

      result = described_class.call(note: target)
      expect(result.mentions.size).to eq(1)
    end

    it "excludes already-linked notes" do
      source = create_note_with_content(title: "Linked", content: "Fala de Neurociência aqui.")
      create(:note_link, src_note: source, dst_note: target, active: true,
        created_in_revision: source.head_revision)

      result = described_class.call(note: target)
      expect(result.mentions).to be_empty
    end

    it "excludes self" do
      # target's own content mentions its own title
      rev = create(:note_revision, note: target, content_markdown: "Neurociência é interessante.")
      target.update_columns(head_revision_id: rev.id)

      result = described_class.call(note: target)
      expect(result.mentions).to be_empty
    end

    it "excludes deleted notes" do
      deleted = create(:note, :deleted, title: "Deletado")
      rev = create(:note_revision, note: deleted, content_markdown: "Neurociência aparece aqui.")
      deleted.update_columns(head_revision_id: rev.id)

      result = described_class.call(note: target)
      expect(result.mentions).to be_empty
    end

    it "excludes mentions inside wikilinks" do
      create_note_with_content(
        title: "Linked Only",
        content: "Referência: [[Neurociência|#{target.id}]] apenas."
      )

      result = described_class.call(note: target)
      expect(result.mentions).to be_empty
    end

    it "returns context snippets with <mark> wrapping" do
      create_note_with_content(
        title: "Artigo",
        content: "A área de Neurociência computacional é fascinante."
      )

      result = described_class.call(note: target)
      snippet = result.mentions.first.snippets.first
      expect(snippet).to include("<mark>")
      expect(snippet).to include("Neurociência")
    end

    it "returns empty when no mentions exist" do
      result = described_class.call(note: target)
      expect(result.mentions).to be_empty
    end

    it "deduplicates source notes matching by title and alias" do
      create(:note_alias, note: target, name: "neuro")
      create_note_with_content(
        title: "Artigo",
        content: "Neurociência e neuro são a mesma coisa."
      )

      result = described_class.call(note: target)
      expect(result.mentions.size).to eq(1)
    end
  end
end
