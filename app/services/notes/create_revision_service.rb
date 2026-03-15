module Notes
  class CreateRevisionService
    CHANGE_THRESHOLD_CHARS = 200
    CHANGE_THRESHOLD_RATIO = 0.05

    def self.call(note:, content_markdown:, author: nil)
      new(note:, content_markdown:, author:).call
    end

    def initialize(note:, content_markdown:, author: nil)
      @note = note
      @content_markdown = content_markdown.to_s
      @author = author
    end

    def call
      if significant_change?
        revision = create_revision!
        {revision:, created: true}
      else
        {revision: @note.head_revision, created: false}
      end
    end

    private

    def significant_change?
      current = @note.head_revision&.content_markdown.to_s
      return true if current.empty?

      diff = (@content_markdown.length - current.length).abs
      ratio = current.length > 0 ? diff.to_f / current.length : 1.0

      diff >= CHANGE_THRESHOLD_CHARS || ratio >= CHANGE_THRESHOLD_RATIO
    end

    def create_revision!
      revision = nil
      ActiveRecord::Base.transaction do
        revision = @note.note_revisions.create!(
          content_markdown: @content_markdown,
          author: @author,
          base_revision_id: @note.head_revision_id
        )
        @note.update_column(:head_revision_id, revision.id)
        @note.touch
      end
      revision
    end
  end
end
