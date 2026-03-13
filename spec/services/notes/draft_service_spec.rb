require "rails_helper"

RSpec.describe Notes::DraftService do
  let(:note) { create(:note) }
  let!(:dst_note) { create(:note, title: "Destino") }

  describe ".call" do
    it "creates a draft revision" do
      expect {
        described_class.call(note: note, content: "# Draft content")
      }.to change(NoteRevision, :count).by(1)

      expect(note.note_revisions.last.revision_kind).to eq("draft")
    end

    it "replaces existing draft (upsert — one draft per note)" do
      described_class.call(note: note, content: "first draft")

      expect {
        described_class.call(note: note, content: "second draft")
      }.not_to change(NoteRevision, :count)

      expect(note.note_revisions.where(revision_kind: :draft).count).to eq(1)
      expect(note.note_revisions.where(revision_kind: :draft).first.content_markdown).to eq("second draft")
    end

    it "does not update head_revision_id" do
      head = create(:note_revision, note: note)
      note.update_columns(head_revision_id: head.id)

      described_class.call(note: note, content: "draft content")
      expect(note.reload.head_revision_id).to eq(head.id)
    end

    it "does not touch existing checkpoints" do
      create(:note_revision, note: note, revision_kind: :checkpoint)

      described_class.call(note: note, content: "draft")
      expect(note.note_revisions.where(revision_kind: :checkpoint).count).to eq(1)
    end

    it "syncs note links against the latest draft content" do
      described_class.call(note: note, content: "[[Destino|#{dst_note.id}]]")

      expect(note.outgoing_links.find_by(dst_note_id: dst_note.id)).to be_present
      expect(note.outgoing_links.last.created_in_revision.revision_kind).to eq("draft")
    end
  end
end
