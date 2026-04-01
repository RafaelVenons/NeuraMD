require "rails_helper"

RSpec.describe Links::DisplayTextUpdateService, type: :service do
  let(:user) { create(:user) }
  let(:target) { create(:note, title: "Original Title") }

  def create_linking_note(title:, content:)
    note = create(:note, title: title)
    revision = create(:note_revision, note: note, revision_kind: :checkpoint, content_markdown: content)
    note.update_columns(head_revision_id: revision.id)
    NoteLink.create!(src_note_id: note.id, dst_note_id: target.id, created_in_revision: revision)
    note
  end

  describe ".call" do
    it "updates display text in wikilinks pointing to the renamed note" do
      src = create_linking_note(
        title: "Source Note",
        content: "Check out [[Original Title|#{target.id}]] for details."
      )

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      expect(src.head_revision.content_markdown).to include("[[New Title|#{target.id}]]")
      expect(src.head_revision.content_markdown).not_to include("Original Title")
    end

    it "preserves role prefixes" do
      src = create_linking_note(
        title: "Source Note",
        content: "Parent: [[Original Title|f:#{target.id}]]"
      )

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      expect(src.head_revision.content_markdown).to include("[[New Title|f:#{target.id}]]")
    end

    it "updates multiple wikilinks in the same note" do
      src = create_linking_note(
        title: "Source Note",
        content: "First: [[Original Title|#{target.id}]] and again: [[Original Title|c:#{target.id}]]"
      )

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      content = src.head_revision.content_markdown
      expect(content).to include("[[New Title|#{target.id}]]")
      expect(content).to include("[[New Title|c:#{target.id}]]")
    end

    it "updates wikilinks across multiple source notes" do
      src1 = create_linking_note(title: "Source 1", content: "Link [[Original Title|#{target.id}]]")
      src2 = create_linking_note(title: "Source 2", content: "Link [[Original Title|#{target.id}]]")

      described_class.call(renamed_note_id: target.id, new_title: "New Title")

      expect(src1.reload.head_revision.content_markdown).to include("[[New Title|#{target.id}]]")
      expect(src2.reload.head_revision.content_markdown).to include("[[New Title|#{target.id}]]")
    end

    it "creates a checkpoint for each updated note" do
      src = create_linking_note(title: "Source Note", content: "Link [[Original Title|#{target.id}]]")
      original_revision_id = src.head_revision_id

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      expect(src.head_revision_id).not_to eq(original_revision_id)
      expect(src.head_revision.revision_kind).to eq("checkpoint")
    end

    it "skips notes where display text already matches" do
      src = create_linking_note(title: "Source Note", content: "Link [[New Title|#{target.id}]]")
      original_revision_id = src.head_revision_id

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      expect(src.head_revision_id).to eq(original_revision_id)
    end

    it "does not affect wikilinks to other notes" do
      other = create(:note, title: "Other Note")
      src = create_linking_note(
        title: "Source Note",
        content: "Target: [[Original Title|#{target.id}]] Other: [[Other Note|#{other.id}]]"
      )

      described_class.call(renamed_note_id: target.id, new_title: "New Title")
      src.reload

      content = src.head_revision.content_markdown
      expect(content).to include("[[New Title|#{target.id}]]")
      expect(content).to include("[[Other Note|#{other.id}]]")
    end

    it "handles blank new_title gracefully" do
      create_linking_note(title: "Source Note", content: "Link [[Original Title|#{target.id}]]")

      expect { described_class.call(renamed_note_id: target.id, new_title: "") }.not_to raise_error
    end
  end
end
