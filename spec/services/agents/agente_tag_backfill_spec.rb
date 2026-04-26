require "rails_helper"

RSpec.describe Agents::AgenteTagBackfill do
  def tagged(note, *names)
    names.each do |name|
      tag = Tag.find_or_create_by!(name: name) { |t| t.color_hex = "#888888"; t.tag_scope = "both" }
      NoteTag.create!(note: note, tag: tag)
    end
    note.reload
  end

  def carries_agente_tag?(note)
    note.reload.tags.exists?(name: described_class::AGENT_TAG_NAME)
  end

  describe ".ensure!" do
    it "creates the `agente` tag when absent and tags every charter that carries an `agente-{role}` tag" do
      uxui = create(:note, :with_head_revision, title: "UX/UI")
      tagged(uxui, "agente-uxui")
      rubi = create(:note, :with_head_revision, title: "Rubi")
      tagged(rubi, "agente-rubi", "agente-team")

      expect(Tag.find_by(name: "agente")).to be_nil

      described_class.ensure!

      expect(Tag.find_by(name: "agente")).to be_present
      expect(carries_agente_tag?(uxui)).to be true
      expect(carries_agente_tag?(rubi)).to be true
    end

    it "leaves the `agente` tag in place when it already exists (no duplicate)" do
      Tag.create!(name: "agente", tag_scope: "both")

      expect { described_class.ensure! }
        .not_to change { Tag.where(name: "agente").count }.from(1)
    end

    it "skips notes whose only matching tag is `agente-team` or its descendants" do
      umbrella_only = create(:note, :with_head_revision, title: "Umbrella only")
      tagged(umbrella_only, "agente-team")

      template = create(:note, :with_head_revision, title: "Charter template")
      tagged(template, "agente-team-template")

      raiz = create(:note, :with_head_revision, title: "Raiz do time")
      tagged(raiz, "agente-team-raiz")

      described_class.ensure!

      expect(carries_agente_tag?(umbrella_only)).to be false
      expect(carries_agente_tag?(template)).to be false
      expect(carries_agente_tag?(raiz)).to be false
    end

    it "skips notes that carry no `agente-*` tag at all" do
      bystander = create(:note, :with_head_revision, title: "Bystander")
      tagged(bystander, "plan", "spec")

      described_class.ensure!

      expect(carries_agente_tag?(bystander)).to be false
    end

    it "is idempotent — re-running does not duplicate NoteTags" do
      charter = create(:note, :with_head_revision, title: "Especialista")
      tagged(charter, "agente-especialista-neuramd")

      described_class.ensure!
      first_count = NoteTag.where(note_id: charter.id).count
      expect(first_count).to be > 0

      expect { described_class.ensure! }
        .not_to change { NoteTag.where(note_id: charter.id).count }.from(first_count)
    end

    it "preserves an existing (note_id, tag_id) row instead of inserting a duplicate" do
      charter = create(:note, :with_head_revision, title: "DevOps")
      tagged(charter, "agente-devops", "agente")

      expect { described_class.ensure! }
        .not_to change { NoteTag.where(note_id: charter.id, tag_id: Tag.find_by!(name: "agente").id).count }.from(1)
    end
  end
end
