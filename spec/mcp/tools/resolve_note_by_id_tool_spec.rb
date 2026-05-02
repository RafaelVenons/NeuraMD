require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ResolveNoteByIdTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("resolve_note_by_id")
    expect(described_class.description_value).to be_present
  end

  describe "with an existing note" do
    let!(:note) { create(:note, :with_head_revision, title: "Minha Nota") }

    before do
      tag = create(:tag, name: "plan")
      note.tags << tag
    end

    it "returns slug, title and tags" do
      response = described_class.call(id: note.id)
      content = JSON.parse(response.content.first[:text])

      expect(content["id"]).to eq(note.id)
      expect(content["slug"]).to eq(note.slug)
      expect(content["title"]).to eq("Minha Nota")
      expect(content["tags"]).to include("plan")
    end

    it "is not an error response" do
      response = described_class.call(id: note.id)
      expect(response.error?).to be false
    end
  end

  describe "with a deleted note" do
    let!(:note) { create(:note, :with_head_revision, title: "Deletada", deleted_at: Time.current) }

    it "returns error 404" do
      response = described_class.call(id: note.id)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include(note.id)
    end
  end

  describe "with unknown UUID" do
    let(:unknown_id) { SecureRandom.uuid }

    it "returns a descriptive error" do
      response = described_class.call(id: unknown_id)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include(unknown_id)
    end
  end

  describe "with invalid UUID format" do
    it "returns a descriptive format error" do
      response = described_class.call(id: "not-a-uuid")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/invalid uuid/i)
    end

    it "rejects an empty string" do
      response = described_class.call(id: "")
      expect(response.error?).to be true
    end
  end
end
