module Api
  class AiRequestsController < BaseController
    def index
      requests = ::AiRequest
        .recent_first
        .limit(50)
        .includes(note_revision: :note)
      render json: {requests: requests.map { |r| serialize(r) }}
    end

    private

    def serialize(request)
      note = request.note_revision&.note
      {
        id: request.id,
        capability: request.capability,
        provider: request.provider,
        status: request.status,
        attempts_count: request.attempts_count,
        max_attempts: request.max_attempts,
        queue_position: request.queue_position,
        last_error_kind: request.last_error_kind,
        error_message: request.error_message,
        created_at: request.created_at.iso8601,
        note: note ? {slug: note.slug, title: note.title} : nil
      }
    end
  end
end
