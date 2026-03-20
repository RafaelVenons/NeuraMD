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
      revision = call
      expect(revision).to be_a(NoteRevision)
      expect(revision.revision_kind).to eq("checkpoint")
    end

    it "updates note.head_revision_id" do
      old_head = note.head_revision_id
      revision = call
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

    it "removes wiki-links no longer in content" do
      dst = create(:note)
      # First checkpoint with link
      call("[[Target|#{dst.id}]]\n\n" + ("content. " * 10))
      expect(note.outgoing_links.count).to eq(1)

      # Second checkpoint without link
      call("No links.\n\n" + ("content. " * 10))
      expect(note.reload.outgoing_links.count).to eq(0)
    end

    it "sets base_revision_id to the previous checkpoint" do
      old_head_id = note.head_revision_id
      revision = call
      expect(revision.base_revision_id).to eq(old_head_id)
    end

    it "marks the checkpoint as AI-generated when linked to an accepted ai request" do
      request = create(:ai_request, note_revision: note.head_revision, status: "succeeded", metadata: {"language" => "pt-BR"})

      revision = call("# Checkpoint com IA\n\n" + ("content. " * 10), accepted_ai_request: request)

      expect(revision.ai_generated).to be(true)
      expect(request.reload.metadata).to include(
        "accepted_checkpoint_revision_id" => revision.id,
        "accepted_by_id" => nil
      )
      expect(request.metadata["accepted_at"]).to be_present
    end
  end
end
