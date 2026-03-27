module Ai
  class ReviewJob < ApplicationJob
    queue_as :airch

    discard_on ActiveJob::DeserializationError

    def perform(ai_request_id)
      request = AiRequest.find(ai_request_id)
      return if request.canceled?

      outcome = ReviewService.process_request!(request)

      if outcome.is_a?(Hash) && !request.reload.canceled?
        if outcome[:status] == :retrying
          self.class.set(wait: outcome[:wait]).perform_later(request.id)
        elsif outcome[:status] == :deferred
          self.class.set(wait: outcome[:wait]).perform_later(request.id)
        end
      end
    rescue Ai::Error
      nil
    end
  end
end
