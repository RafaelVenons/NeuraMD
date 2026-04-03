require "rails_helper"

RSpec.describe Search::NoteQueryService do
  let(:scope) { Note.all }

  describe "alias search" do
    let!(:note) { create(:note, :with_head_revision, title: "Hematologia") }

    before do
      create(:note_alias, note: note, name: "Blood Science")
    end

    it "finds note by alias name" do
      result = described_class.call(scope: scope, query: "Blood Science")

      expect(result.notes.map(&:id)).to include(note.id)
    end

    it "finds note by fuzzy alias match" do
      result = described_class.call(scope: scope, query: "blood scien")

      expect(result.notes.map(&:id)).to include(note.id)
    end

    it "still finds notes by title" do
      result = described_class.call(scope: scope, query: "Hematologia")

      expect(result.notes.map(&:id)).to include(note.id)
    end

    it "does not duplicate results when note matches both title and alias" do
      create(:note_alias, note: note, name: "Hemato")
      result = described_class.call(scope: scope, query: "Hemato")

      ids = result.notes.map(&:id)
      expect(ids.count(note.id)).to eq(1)
    end

    it "works for notes without aliases" do
      plain = create(:note, :with_head_revision, title: "Neurologia Simples")
      result = described_class.call(scope: scope, query: "Neurologia")

      expect(result.notes.map(&:id)).to include(plain.id)
    end
  end

  describe "DSL integration" do
    let(:user) { create(:user) }

    def create_noted(title, content: "Conteudo de #{title}")
      note = create(:note, title: title)
      Notes::CheckpointService.call(note: note, content: content, author: user)
      note.reload
    end

    it "filters by DSL operator and returns matching notes" do
      tag = create(:tag, name: "neuro")
      tagged = create_noted("Neurociencia")
      NoteTag.create!(note: tagged, tag: tag)
      _other = create_noted("Cardiologia")

      result = described_class.call(scope: scope, query: "tag:neuro")
      expect(result.notes.map(&:id)).to include(tagged.id)
      expect(result.notes.map(&:id)).not_to include(_other.id)
    end

    it "combines DSL filter with text search" do
      tag = create(:tag, name: "medicina")
      match = create_noted("Hematologia Avancada", content: "Estudo avancado de hematologia clinica")
      NoteTag.create!(note: match, tag: tag)
      tagged_no_match = create_noted("XYZQWK Topico Diferente", content: "Conteudo completamente diferente sem relacao")
      NoteTag.create!(note: tagged_no_match, tag: tag)

      result = described_class.call(scope: scope, query: "tag:medicina Hematologia")
      expect(result.notes.map(&:id)).to include(match.id)
      expect(result.notes.map(&:id)).not_to include(tagged_no_match.id)
    end

    it "falls through to text search when no valid operators are present" do
      note = create_noted("Neurologia Simples")
      result = described_class.call(scope: scope, query: "Neurologia")

      expect(result.notes.map(&:id)).to include(note.id)
      expect(result.dsl_errors).to be_empty
    end

    it "returns dsl_errors for invalid operators without crashing" do
      _note = create_noted("Test Note")
      result = described_class.call(scope: scope, query: "orphan:maybe test")

      expect(result.dsl_errors).not_to be_empty
      expect(result.dsl_errors.first[:operator]).to eq(:orphan)
    end

    it "handles DSL-only query with no text portion" do
      tag = create(:tag, name: "ref")
      note = create_noted("Reference")
      NoteTag.create!(note: note, tag: tag)

      result = described_class.call(scope: scope, query: "tag:ref")
      expect(result.notes.map(&:id)).to include(note.id)
    end
  end
end
