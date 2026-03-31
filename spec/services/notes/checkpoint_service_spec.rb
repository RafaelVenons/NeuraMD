require "rails_helper"

RSpec.describe Notes::CheckpointService do
  let(:note) { create(:note, :with_head_revision) }

  def call(content = "# Checkpoint\n\n" + ("content. " * 30), **opts)
    described_class.call(note: note, content: content, **opts)
  end

  describe ".call" do
    it "creates a checkpoint revision" do
      expect { call }.to change { note.note_revisions.where(revision_kind: :checkpoint).count }.by(1)
    end

    it "returns the new NoteRevision" do
      revision = call.revision
      expect(revision).to be_a(NoteRevision)
      expect(revision.revision_kind).to eq("checkpoint")
    end

    it "updates note.head_revision_id" do
      old_head = note.head_revision_id
      revision = call.revision
      expect(note.reload.head_revision_id).to eq(revision.id)
      expect(note.head_revision_id).not_to eq(old_head)
    end

    it "deletes any existing draft" do
      Notes::DraftService.call(note: note, content: "draft before checkpoint")
      expect(note.note_revisions.where(revision_kind: :draft).count).to eq(1)

      call
      expect(note.note_revisions.reload.where(revision_kind: :draft).count).to eq(0)
    end

    it "synchronises wiki-links from content" do
      dst = create(:note)
      content = "[[Target|#{dst.id}]]\n\n" + ("content. " * 10)

      expect { call(content) }.to change(NoteLink, :count).by(1)
      expect(note.outgoing_links.last.dst_note_id).to eq(dst.id)
    end

    it "returns graph_changed true when checkpoint updates active links" do
      dst = create(:note)
      result = call("[[Target|#{dst.id}]]\n\n" + ("content. " * 10))

      expect(result.graph_changed).to be(true)
      expect(result.revision).to be_a(NoteRevision)
    end

    it "removes wiki-links no longer in content" do
      dst = create(:note)
      # First checkpoint with link
      call("[[Target|#{dst.id}]]\n\n" + ("content. " * 10))
      expect(note.outgoing_links.count).to eq(1)

      # Second checkpoint without link
      call("No links.\n\n" + ("content. " * 10))
      expect(note.reload.active_outgoing_links.count).to eq(0)
      expect(note.outgoing_links.find_by(dst_note_id: dst.id)).not_to be_active
    end

    it "sets base_revision_id to the previous checkpoint" do
      old_head_id = note.head_revision_id
      revision = call.revision
      expect(revision.base_revision_id).to eq(old_head_id)
    end

    it "carries forward properties_data from the previous head revision" do
      note.head_revision.update!(properties_data: {"status" => "draft"})
      revision = call.revision
      expect(revision.properties_data).to eq({"status" => "draft"})
    end

    it "uses explicit properties_data when provided" do
      note.head_revision.update!(properties_data: {"status" => "draft"})
      revision = call("content", properties_data: {"status" => "published", "priority" => 1}).revision
      expect(revision.properties_data).to eq({"status" => "published", "priority" => 1})
    end

    it "defaults to empty hash when note has no head revision" do
      note.update_columns(head_revision_id: nil)
      revision = call.revision
      expect(revision.properties_data).to eq({})
    end

    it "marks the checkpoint as AI-generated when linked to an accepted ai request" do
      request = create(:ai_request, note_revision: note.head_revision, status: "succeeded", metadata: {"language" => "pt-BR"})

      revision = call("# Checkpoint com IA\n\n" + ("content. " * 10), accepted_ai_request: request).revision

      expect(revision.ai_generated).to be(true)
      expect(request.reload.metadata).to include(
        "accepted_checkpoint_revision_id" => revision.id,
        "accepted_by_id" => nil
      )
      expect(request.metadata["accepted_at"]).to be_present
    end
  end
end
