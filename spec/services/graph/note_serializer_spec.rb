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

  describe "avatar" do
    let(:note) do
      n = create(:note, :with_head_revision, title: "Especialista NeuraMD")
      tagged(n, "agente-team", "agente-especialista-neuramd")
    end

    context "when the note is not an agent" do
      it "omits the avatar key entirely" do
        plain = create(:note, :with_head_revision, title: "Plain")
        payload = described_class.call(plain)
        expect(payload).not_to have_key(:avatar)
      end

      it "omits avatar for agente-team-template (template is not a real agent)" do
        template = create(:note, :with_head_revision, title: "Template")
        tagged(template, "agente-team", "agente-team-template")
        payload = described_class.call(template)
        expect(payload).not_to have_key(:avatar)
      end
    end

    context "when the note is an agent without explicit properties" do
      it "derives color from the first matching role tag" do
        payload = described_class.call(note)
        expect(payload[:avatar][:color]).to eq(Agents::AvatarPalette::ROLE_COLORS.fetch("agente-especialista-neuramd"))
      end

      it "uses DEFAULT_VARIANT and DEFAULT_HAT" do
        payload = described_class.call(note)
        expect(payload[:avatar][:variant]).to eq("clawd-v1")
        expect(payload[:avatar][:hat]).to eq("none")
      end

      it "falls back to AvatarPalette::DEFAULT_COLOR when no role tag matches" do
        agent = create(:note, :with_head_revision, title: "Orphan agent")
        tagged(agent, "agente-team")
        payload = described_class.call(agent)
        expect(payload[:avatar][:color]).to eq(Agents::AvatarPalette::DEFAULT_COLOR)
      end
    end

    context "when the note has explicit avatar properties" do
      it "prefers note properties over defaults" do
        note.head_revision.update!(
          properties_data: {
            "avatar_color" => "#ff00aa",
            "avatar_hat" => "cartola",
            "avatar_variant" => "clawd-v2"
          }
        )
        note.reload
        payload = described_class.call(note)
        expect(payload[:avatar]).to include(
          color: "#ff00aa",
          hat: "cartola",
          variant: "clawd-v2"
        )
      end

      it "ignores blank property values and falls back to defaults" do
        note.head_revision.update!(
          properties_data: {"avatar_color" => "", "avatar_hat" => nil}
        )
        note.reload
        payload = described_class.call(note)
        expect(payload[:avatar][:color]).to eq(Agents::AvatarPalette::ROLE_COLORS.fetch("agente-especialista-neuramd"))
        expect(payload[:avatar][:hat]).to eq("none")
      end
    end

    describe "state" do
      it "is sleeping by default (no alive session set)" do
        payload = described_class.call(note)
        expect(payload[:avatar][:state]).to eq("sleeping")
      end

      it "is sleeping when the note id is not in the alive tentacle set" do
        other = SecureRandom.uuid
        payload = described_class.call(note, alive_tentacle_note_ids: Set[other])
        expect(payload[:avatar][:state]).to eq("sleeping")
      end

      it "is awake when the note id is in the alive tentacle set" do
        payload = described_class.call(note, alive_tentacle_note_ids: Set[note.id])
        expect(payload[:avatar][:state]).to eq("awake")
      end

      it "accepts a plain Array too (caller convenience)" do
        payload = described_class.call(note, alive_tentacle_note_ids: [note.id])
        expect(payload[:avatar][:state]).to eq("awake")
      end
    end
  end
end
