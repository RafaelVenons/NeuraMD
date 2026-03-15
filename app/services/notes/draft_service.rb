module Notes
  # Upserts a draft revision for a note (at most one draft per note at any time).
  # Drafts are for crash protection and auto-save — they do NOT appear in the
  # revision history, but they do update the current link graph so link tags
  # can be attached against the latest saved content.
  #
  # Returns the draft NoteRevision.
  class DraftService
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
        @note.note_revisions.where(revision_kind: :draft).destroy_all
        draft = @note.note_revisions.create!(
          content_markdown: @content,
          revision_kind: :draft,
          author: @author
        )

        Links::SyncService.call(src_note: @note, revision: draft, content: @content)

        draft
      end
    end
  end
end
