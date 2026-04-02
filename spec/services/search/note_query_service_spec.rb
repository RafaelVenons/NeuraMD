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
end
