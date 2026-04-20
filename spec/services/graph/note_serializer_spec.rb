require "rails_helper"

RSpec.describe Graph::NoteSerializer do
  def tagged(note, *names)
    names.each do |name|
      tag = Tag.find_or_create_by!(name: name) { |t| t.color_hex = "#888888"; t.tag_scope = "both" }
      NoteTag.create!(note: note, tag: tag)
    end
    note.reload
  end

  describe "node_type" do
    it "is leaf by default" do
      note = create(:note, :with_head_revision, title: "Plain")
      payload = described_class.call(note)
      expect(payload[:node_type]).to eq("leaf")
    end

    it "is structure when the note carries an {acervo}-estrutura tag" do
      note = create(:note, :with_head_revision, title: "Structure")
      tagged(note, "plan-estrutura")
      payload = described_class.call(note)
      expect(payload[:node_type]).to eq("structure")
    end

    it "is root when the note carries an {acervo}-raiz tag" do
      note = create(:note, :with_head_revision, title: "Root")
      tagged(note, "plan-raiz")
      payload = described_class.call(note)
      expect(payload[:node_type]).to eq("root")
    end

    it "prefers root over structure when both tags are present" do
      note = create(:note, :with_head_revision, title: "Both")
      tagged(note, "plan-estrutura", "plan-raiz")
      payload = described_class.call(note)
      expect(payload[:node_type]).to eq("root")
    end

    it "is tentacle when the note carries the tentacle tag, overriding acervo role" do
      note = create(:note, :with_head_revision, title: "Tentacle")
      tagged(note, "plan-raiz", "tentacle")
      payload = described_class.call(note)
      expect(payload[:node_type]).to eq("tentacle")
    end
  end
end
