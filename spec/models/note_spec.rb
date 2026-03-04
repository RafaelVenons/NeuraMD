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
