module Ai
  class ReviewJob < ApplicationJob
    queue_as :ai_remote

    discard_on ActiveJob::DeserializationError

    def perform(ai_request_id)
      request = AiRequest.find(ai_request_id)
      return if request.canceled?

      outcome = ReviewService.process_request!(request)

      if outcome.is_a?(Hash) && outcome[:status] == :retrying && !request.reload.canceled?
        self.class.set(wait: outcome[:wait]).perform_later(request.id)
      end
    rescue Ai::Error
      nil
    end
  end
end
