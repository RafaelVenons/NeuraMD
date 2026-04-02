require "rails_helper"

RSpec.describe Links::ResolveService do
  describe ".call" do
    it "returns not_found when no note matches the title" do
      result = described_class.call(title: "Nonexistent Note")
      expect(result.status).to eq(:not_found)
      expect(result.notes).to eq([])
      expect(result.match_kind).to be_nil
    end

    it "resolves by exact title (case-insensitive)" do
      note = create(:note, title: "Mapa Mental")
      result = described_class.call(title: "mapa mental")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note])
      expect(result.match_kind).to eq(:exact_title)
    end

    it "excludes soft-deleted notes" do
      create(:note, :deleted, title: "Deleted Note")
      result = described_class.call(title: "Deleted Note")
      expect(result.status).to eq(:not_found)
    end

    it "excludes the note identified by exclude_id" do
      note = create(:note, title: "Self Reference")
      result = described_class.call(title: "Self Reference", exclude_id: note.id)
      expect(result.status).to eq(:not_found)
    end

    it "resolves by exact alias (case-insensitive)" do
      note = create(:note, title: "Neurociência Computacional")
      create(:note_alias, note: note, name: "neurocomp")
      result = described_class.call(title: "NeuroComp")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note])
      expect(result.match_kind).to eq(:exact_alias)
    end

    it "returns ambiguous when title matches one note and alias matches another" do
      note_a = create(:note, title: "Café Especial")
      note_b = create(:note, title: "Outra Nota")
      create(:note_alias, note: note_b, name: "Café Especial")
      result = described_class.call(title: "Café Especial")
      expect(result.status).to eq(:ambiguous)
      expect(result.notes).to contain_exactly(note_a, note_b)
    end

    it "precedence: exact title wins when only one note matches by title" do
      note_a = create(:note, title: "Unique Title XYZ")
      note_b = create(:note, title: "Bar")
      create(:note_alias, note: note_b, name: "unique title xyz alias")
      result = described_class.call(title: "Unique Title XYZ")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note_a])
      expect(result.match_kind).to eq(:exact_title)
    end

    it "resolves by normalized title (accent-insensitive)" do
      note = create(:note, title: "Café")
      result = described_class.call(title: "Cafe")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note])
      expect(result.match_kind).to eq(:normalized)
    end

    it "resolves by normalized alias (accent-insensitive)" do
      note = create(:note, title: "Some Note")
      create(:note_alias, note: note, name: "résumé")
      result = described_class.call(title: "resume")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note])
      expect(result.match_kind).to eq(:normalized)
    end

    it "returns ambiguous on normalized match with multiple candidates" do
      note_a = create(:note, title: "Café")
      note_b = create(:note, title: "Outra")
      create(:note_alias, note: note_b, name: "cafê")
      result = described_class.call(title: "cafe")
      expect(result.status).to eq(:ambiguous)
      expect(result.notes).to contain_exactly(note_a, note_b)
    end

    it "precedence: exact match wins over normalized match" do
      note_exact = create(:note, title: "Cafe")
      create(:note, title: "Café")
      result = described_class.call(title: "Cafe")
      expect(result.status).to eq(:resolved)
      expect(result.notes).to eq([note_exact])
      expect(result.match_kind).to eq(:exact_title)
    end
  end
end
