module Notes
  # Upserts a draft revision for a note (at most one draft per note at any time).
  # Drafts are for crash protection and auto-save — they do NOT appear in the
  # revision history, but they do update the current link graph so link tags
  # can be attached against the latest saved content.
  #
  # Returns the draft NoteRevision and whether the active link graph changed.
  class DraftService
    Result = Struct.new(:revision, :graph_changed, keyword_init: true)

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
        previous_draft_ids = @note.note_revisions.where(revision_kind: :draft).pluck(:id)
        draft = @note.note_revisions.create!(
          content_markdown: @content,
          revision_kind: :draft,
          author: @author,
          base_revision_id: @note.head_revision_id
        )

        sync_result = Links::SyncService.call(src_note: @note, revision: draft, content: @content)

        if previous_draft_ids.any?
          AiRequest.where(note_revision_id: previous_draft_ids).update_all(note_revision_id: draft.id, updated_at: Time.current)
          @note.outgoing_links.where(created_in_revision_id: previous_draft_ids).update_all(created_in_revision_id: draft.id)
          @note.note_revisions.where(id: previous_draft_ids).destroy_all
        end

        Result.new(revision: draft, graph_changed: sync_result.graph_changed)
      end
    end
  end
end
