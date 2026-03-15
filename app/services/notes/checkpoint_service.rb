module Notes
  # Creates a permanent checkpoint revision and synchronises wiki-links.
  # Checkpoints appear in the revision history and trigger link sync.
  # Also deletes any existing draft for this note (checkpoint supersedes draft).
  #
  # Returns the new NoteRevision checkpoint.
  class CheckpointService
    def self.call(note:, content:, author: nil)
      new(note:, content:, author:).call
    end

    def initialize(note:, content:, author:)
      @note = note
      @content = content
      @author = author
    end

    def call
      ActiveRecord::Base.transaction do
        draft_ids = @note.note_revisions.where(revision_kind: :draft).pluck(:id)

        # Resolve latest checkpoint from DB (head_revision_id may be stale if it pointed to a draft)
        latest_checkpoint_id = @note.note_revisions
          .where(revision_kind: :checkpoint)
          .order(created_at: :desc)
          .pick(:id)

        revision = @note.note_revisions.create!(
          content_markdown: @content,
          revision_kind: :checkpoint,
          author: @author,
          base_revision_id: latest_checkpoint_id
        )

        @note.update!(head_revision_id: revision.id)

        Links::SyncService.call(src_note: @note, revision: revision, content: @content)

        if draft_ids.any?
          @note.outgoing_links.where(created_in_revision_id: draft_ids).update_all(created_in_revision_id: revision.id)
          @note.note_revisions.where(id: draft_ids).destroy_all
        end

        revision
      end
    end
  end
end
