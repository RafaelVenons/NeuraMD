require "rails_helper"

RSpec.describe Mentions::LinkService do
  let(:user) { create(:user) }
  let(:target) { create(:note, :with_head_revision, title: "Neurociência") }

  def create_note_with_content(title:, content:)
    note = create(:note, title: title)
    rev = create(:note_revision, note: note, content_markdown: content, revision_kind: :checkpoint)
    note.update_columns(head_revision_id: rev.id)
    note
  end

  describe ".call" do
    it "converts plain text mention to wikilink" do
      source = create_note_with_content(title: "Artigo", content: "Estudo de Neurociência avançada.")

      result = described_class.call(source_note: source, target_note: target, matched_term: "Neurociência", author: user)

      source.reload
      expect(source.head_revision.content_markdown).to include("[[Neurociência|#{target.id}]]")
      expect(source.head_revision.content_markdown).to include("avançada")
    end

    it "creates a checkpoint revision" do
      source = create_note_with_content(title: "Artigo", content: "Neurociência é fascinante.")

      expect {
        described_class.call(source_note: source, target_note: target, matched_term: "Neurociência", author: user)
      }.to change { source.note_revisions.checkpoint.count }.by(1)
    end

    it "replaces only the first occurrence" do
      source = create_note_with_content(
        title: "Artigo",
        content: "Neurociência A e Neurociência B."
      )

      described_class.call(source_note: source, target_note: target, matched_term: "Neurociência", author: user)

      source.reload
      content = source.head_revision.content_markdown
      expect(content.scan("[[Neurociência|#{target.id}]]").size).to eq(1)
      expect(content).to include("Neurociência B")
      expect(content).not_to include("[[Neurociência|#{target.id}]] B")
    end

    it "does not touch mentions inside existing wikilinks" do
      source = create_note_with_content(
        title: "Artigo",
        content: "Link: [[Neurociência|#{target.id}]] e Neurociência aqui."
      )

      described_class.call(source_note: source, target_note: target, matched_term: "Neurociência", author: user)

      source.reload
      content = source.head_revision.content_markdown
      # The existing wikilink should remain, and the plain mention should be converted
      expect(content.scan("[[Neurociência|#{target.id}]]").size).to eq(2)
    end

    it "returns graph_changed" do
      source = create_note_with_content(title: "Artigo", content: "Neurociência é incrível.")

      result = described_class.call(source_note: source, target_note: target, matched_term: "Neurociência", author: user)

      expect(result.graph_changed).to be true
    end
  end
end
