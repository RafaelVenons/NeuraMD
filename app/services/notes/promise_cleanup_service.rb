module Notes
  class PromiseCleanupService
    Result = Struct.new(:note_deleted, :request_canceled, :source_content, :graph_changed, keyword_init: true)

    def self.call(ai_request:)
      new(ai_request:).call
    end

    def initialize(ai_request:)
      @ai_request = ai_request
    end

    def call
      request_canceled = false
      note_deleted = false
      graph_changed = false

      if @ai_request.active?
        Ai::ReviewService.cancel_request!(@ai_request)
        request_canceled = true
      end

      note = Note.active.find_by(id: metadata["promise_note_id"])
      if note.present?
        note.soft_delete!
        note_deleted = true
      end

      source_content, graph_changed = revert_source_markup

      stamp_metadata("promise_cleanup_at" => Time.current.iso8601)

      Result.new(note_deleted:, request_canceled:, source_content:, graph_changed:)
    end

    private

    def metadata
      @ai_request.metadata || {}
    end

    def stamp_metadata(extra)
      @ai_request.update!(metadata: metadata.merge(extra))
    end

    def revert_source_markup
      source_note = Note.active.find_by(id: metadata["promise_source_note_id"])
      return [nil, false] if source_note.blank?

      author = User.find_by(id: metadata["requested_by_id"])
      current_revision = source_note.note_revisions.find_by(revision_kind: :draft) || source_note.head_revision
      current_content = current_revision&.content_markdown.to_s
      return [nil, false] if current_content.blank?

      restored = current_content.gsub(link_markup_re) { "[[#{$1}]]" }
      return [nil, false] if restored == current_content

      result = Notes::DraftService.call(note: source_note, content: restored, author:)
      [result.revision.content_markdown, result.graph_changed]
    end

    def link_markup_re
      note_id = Regexp.escape(metadata["promise_note_id"].to_s)
      /\[\[([^\]|]+)\|(?:[a-z]+:)?#{note_id}\]\]/i
    end
  end
end
