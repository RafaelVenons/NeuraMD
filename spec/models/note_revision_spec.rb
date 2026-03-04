require "rails_helper"

RSpec.describe NoteRevision, type: :model do
  subject(:revision) { build(:note_revision) }

  describe "associations" do
    it { is_expected.to belong_to(:note) }
    it { is_expected.to belong_to(:author).class_name("User").optional }
    it { is_expected.to belong_to(:base_revision).class_name("NoteRevision").optional }
    it { is_expected.to have_many(:note_tts_assets).dependent(:destroy) }
    it { is_expected.to have_many(:ai_requests).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:content_markdown) }
  end

  describe "content_plain derivation" do
    it "strips markdown syntax when saving" do
      revision = create(:note_revision, content_markdown: "# Título\n\n**bold** e _italic_\n\nhttps://example.com")
      expect(revision.content_plain).not_to include("#")
      expect(revision.content_plain).not_to include("**")
      expect(revision.content_plain).not_to include("https://")
      expect(revision.content_plain).to include("Título")
      expect(revision.content_plain).to include("bold")
    end
  end

  describe "AR Encryption" do
    it "stores content_markdown encrypted" do
      revision = create(:note_revision, content_markdown: "Conteúdo secreto")
      raw = ActiveRecord::Base.connection.execute(
        "SELECT content_markdown FROM note_revisions WHERE id = '#{revision.id}'"
      ).first["content_markdown"]
      expect(raw).not_to eq("Conteúdo secreto")
    end
  end
end
