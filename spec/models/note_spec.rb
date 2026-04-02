require "rails_helper"

RSpec.describe Note, type: :model do
  subject(:note) { build(:note) }

  describe "associations" do
    it { is_expected.to belong_to(:head_revision).class_name("NoteRevision").optional }
    it { is_expected.to have_many(:note_revisions).dependent(:destroy) }
    it { is_expected.to have_many(:outgoing_links).class_name("NoteLink") }
    it { is_expected.to have_many(:incoming_links).class_name("NoteLink") }
    it { is_expected.to have_many(:note_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:note_tags) }
    it { is_expected.to have_many(:note_aliases).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_inclusion_of(:note_kind).in_array(Note::NOTE_KINDS) }

    it "requires slug to be unique (case-insensitive)" do
      existing = create(:note, slug: "minha-nota")
      duplicate = build(:note, title: "Outro Título", slug: "minha-nota")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to be_present
    end

    it "requires slug to be present after generation" do
      note = create(:note, title: "Titulo Válido")
      note.slug = ""
      expect(note).not_to be_valid
    end

    it "prevents slug change after creation" do
      note = create(:note, title: "Original")
      note.slug = "hacked-slug"
      expect(note).not_to be_valid
      expect(note.errors[:slug]).to include("cannot be changed after creation")
    end

    it "allows slug to be set on create" do
      note = create(:note, title: "Qualquer", slug: "custom-slug")
      expect(note.slug).to eq("custom-slug")
    end
  end

  describe "slug generation" do
    it "auto-generates slug from title on create" do
      note = create(:note, title: "Minha Primeira Nota")
      expect(note.slug).to eq("minha-primeira-nota")
    end

    it "generates unique slug when collision exists" do
      create(:note, title: "Nota Duplicada")
      note2 = create(:note, title: "Nota Duplicada")
      expect(note2.slug).to eq("nota-duplicada-1")
    end

    it "respects manually set slug" do
      note = create(:note, slug: "meu-slug-customizado")
      expect(note.slug).to eq("meu-slug-customizado")
    end
  end

  describe ".search_by_title" do
    let!(:cardio) { create(:note, :with_head_revision, title: "Cardiologia") }
    let!(:neuro) { create(:note, :with_head_revision, title: "Neurologia") }

    it "finds notes by title" do
      results = Note.search_by_title("cardio")
      expect(results).to include(cardio)
      expect(results).not_to include(neuro)
    end

    it "finds notes by alias" do
      create(:note_alias, note: neuro, name: "Brain Science")
      results = Note.search_by_title("brain")
      expect(results).to include(neuro)
    end

    it "returns matched_alias when match is via alias" do
      create(:note_alias, note: neuro, name: "Brain Science")
      results = Note.search_by_title("brain")
      matched = results.find { |n| n.id == neuro.id }
      expect(matched.matched_alias).to eq("Brain Science")
    end

    it "does not return matched_alias when match is via title" do
      create(:note_alias, note: cardio, name: "Heart")
      results = Note.search_by_title("cardio")
      matched = results.find { |n| n.id == cardio.id }
      expect(matched.matched_alias).to be_nil
    end

    it "ranks title exact match above alias match" do
      other = create(:note, :with_head_revision, title: "Outro Tema")
      create(:note_alias, note: other, name: "Cardio Avançado")

      results = Note.search_by_title("Cardio")
      # Title-matched "Cardiologia" should come before alias-matched "Outro Tema"
      expect(results.index(cardio)).to be < results.index(other)
    end

    it "respects exclude_id" do
      results = Note.search_by_title("cardio", exclude_id: cardio.id)
      expect(results).not_to include(cardio)
    end
  end

  describe "soft delete" do
    let!(:note) { create(:note) }

    it "soft deletes and restores" do
      note.soft_delete!
      expect(note).to be_deleted
      expect(Note.active).not_to include(note)

      note.restore!
      expect(note).not_to be_deleted
      expect(Note.active).to include(note)
    end
  end
end
