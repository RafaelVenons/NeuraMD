module Notes
  class PromiseFulfillmentService
    def self.call(ai_request:)
      new(ai_request:).call
    end

    def initialize(ai_request:)
      @ai_request = ai_request
    end

    def call
      return unless @ai_request.succeeded?

      note = Note.active.find_by(id: metadata["promise_note_id"])
      return if note.blank?
      return if metadata["promise_checkpoint_revision_id"].present?

      if note.head_revision.present? || note.note_revisions.where(revision_kind: :draft).exists?
        stamp_metadata("promise_delivery_skipped_at" => Time.current.iso8601, "promise_delivery_skipped_reason" => "note_already_has_content")
        return note
      end

      content = @ai_request.output_text.to_s
      return if content.blank?

      author = User.find_by(id: metadata["requested_by_id"])
      result = Notes::CheckpointService.call(note:, content:, author:)

      stamp_metadata(
        "promise_checkpoint_revision_id" => result.revision.id,
        "promise_fulfilled_at" => Time.current.iso8601
      )

      note
    end

    private

    def metadata
      @ai_request.metadata || {}
    end

    def stamp_metadata(extra)
      @ai_request.update!(metadata: metadata.merge(extra))
    end
  end
end
