require "rails_helper"

RSpec.describe Notes::MergeService, type: :service do
  let(:user) { create(:user) }

  let(:source) { create(:note, title: "Source Note") }
  let(:target) { create(:note, title: "Target Note") }

  before do
    Notes::CheckpointService.call(note: source, content: "Source content", author: user)
    Notes::CheckpointService.call(note: target, content: "Target content", author: user)
  end

  describe ".call" do
    it "appends source content to target as a new checkpoint" do
      result = described_class.call(source: source, target: target, author: user)

      target.reload
      head_content = target.head_revision.content_markdown
      expect(head_content).to include("Target content")
      expect(head_content).to include("Source content")
      expect(result.target).to eq(target)
    end

    it "soft-deletes the source note" do
      described_class.call(source: source, target: target, author: user)
      expect(source.reload).to be_deleted
    end

    it "creates a slug redirect from source to target" do
      old_slug = source.slug
      described_class.call(source: source, target: target, author: user)

      redirect = SlugRedirect.find_by(slug: old_slug)
      expect(redirect).to be_present
      expect(redirect.note).to eq(target)
    end

    it "moves incoming links from source to target" do
      linker = create(:note, title: "Linker")
      linker_rev = create(:note_revision, note: linker, revision_kind: :checkpoint,
        content_markdown: "Link to [[Source|#{source.id}]]", author: user)
      linker.update_columns(head_revision_id: linker_rev.id)
      NoteLink.create!(src_note_id: linker.id, dst_note_id: source.id,
        created_in_revision: linker_rev, active: true)

      described_class.call(source: source, target: target, author: user)

      expect(NoteLink.find_by(src_note_id: linker.id, dst_note_id: source.id)).to be_nil
      moved_link = NoteLink.find_by(src_note_id: linker.id, dst_note_id: target.id)
      expect(moved_link).to be_present
      expect(moved_link).to be_active
    end

    it "skips moving a link if source and target already have a link from the same note" do
      linker = create(:note, title: "Linker")
      linker_rev = create(:note_revision, note: linker, revision_kind: :checkpoint,
        content_markdown: "Links to both", author: user)
      linker.update_columns(head_revision_id: linker_rev.id)
      NoteLink.create!(src_note_id: linker.id, dst_note_id: source.id,
        created_in_revision: linker_rev, active: true)
      NoteLink.create!(src_note_id: linker.id, dst_note_id: target.id,
        created_in_revision: linker_rev, active: true)

      described_class.call(source: source, target: target, author: user)

      # The duplicate link to source is deleted, the one to target remains
      expect(NoteLink.where(src_note_id: linker.id, dst_note_id: source.id).count).to eq(0)
      expect(NoteLink.where(src_note_id: linker.id, dst_note_id: target.id).count).to eq(1)
    end

    it "raises ArgumentError when merging a note into itself" do
      expect { described_class.call(source: source, target: source, author: user) }
        .to raise_error(ArgumentError, /cannot merge a note into itself/i)
    end

    it "raises ArgumentError when source is already deleted" do
      source.soft_delete!
      expect { described_class.call(source: source, target: target, author: user) }
        .to raise_error(ArgumentError, /source note is deleted/i)
    end

    it "returns a result with merged content info" do
      result = described_class.call(source: source, target: target, author: user)
      expect(result.source).to eq(source)
      expect(result.target).to eq(target)
      expect(result.revision).to be_a(NoteRevision)
    end
  end
end
