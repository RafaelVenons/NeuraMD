require "digest"
require_relative "error"
require_relative "provider_registry"

module Ai
  class ReviewService
    CAPABILITIES = %w[suggest rewrite grammar_review translate seed_note].freeze
    MAX_ATTEMPTS = 3

    class << self
      def status
        ProviderRegistry.status
      end

      def enqueue(note:, note_revision:, capability:, text:, language:, provider_name: nil, model_name: nil, requested_by: nil, target_language: nil)
        capability = capability.to_s
        raise InvalidCapabilityError, "Capability de IA invalida." unless CAPABILITIES.include?(capability)
        raise Error, "Nenhum texto para processar." if text.to_s.blank?

        selection = ProviderRegistry.resolve_selection(
          provider_name,
          model_name: model_name,
          capability: capability,
          text: text,
          language: language,
          target_language: target_language
        )
        provider = ProviderRegistry.build(
          selection[:name],
          model_name: selection[:model]
        )
        request = note_revision.ai_requests.create!(
          provider: provider.name,
          requested_provider: provider.name,
          capability: capability,
          status: "queued",
          model: provider.model,
          attempts_count: 0,
          max_attempts: MAX_ATTEMPTS,
          input_text: text,
          prompt_summary: prompt_summary(capability, text),
          metadata: {
            "language" => language,
            "target_language" => target_language,
            "note_id" => note.id,
            "requested_by_id" => requested_by&.id,
            "requested_model" => provider.model,
            "model_selection_strategy" => selection[:selection_strategy],
            "model_selection_reason" => selection[:selection_reason]
          }
        )

        Ai::ReviewJob.perform_later(request.id)
        request
      end

      def process_request!(request)
        run_started_at = Time.current

        next_ready = AiRequest.next_ready_request(now: run_started_at)
        return {status: :deferred, wait: 1.second} if next_ready.present? && next_ready.id != request.id
        return {status: :deferred, wait: 1.second} if AiRequest.where(status: "running").where.not(id: request.id).exists?

        request.with_lock do
          return request if request.succeeded?
          return request if request.failed? || request.canceled?

          request.update!(
            status: "running",
            started_at: request.started_at || run_started_at,
            attempts_count: request.attempts_count + 1,
            queue_position: request.queue_position,
            error_message: nil,
            last_error_at: nil,
            last_error_kind: nil,
            next_retry_at: nil
          )
        end

        provider = ProviderRegistry.build(request.requested_provider, model_name: request.metadata["requested_model"])
        result = provider.review(
          capability: request.capability,
          text: request.input_text,
          language: request.metadata["language"],
          target_language: request.metadata["target_language"]
        )

        request.update!(
          status: "succeeded",
          provider: result.provider,
          model: result.model,
          request_hash: request_hash(result:, request:),
          response_summary: result.content.to_s.truncate(240),
          output_text: result.content,
          tokens_in: result.tokens_in,
          tokens_out: result.tokens_out,
          last_error_at: nil,
          last_error_kind: nil,
          next_retry_at: nil,
          completed_at: Time.current
        )
        apply_request_side_effect!(request)
        :succeeded
      rescue Ai::Error => e
        handle_failure!(request, e)
      end

      def cancel_request!(request)
        request.with_lock do
          return request if request.succeeded? || request.failed? || request.canceled?

          request.update!(
            status: "canceled",
            next_retry_at: nil,
            completed_at: Time.current,
            error_message: nil
          )
        end

        request
      end

      def retry_request!(request)
        request.with_lock do
          unless request.failed? || request.canceled?
            raise Error, "Apenas requests finalizadas com falha ou canceladas podem ser reenfileiradas."
          end

          request.update!(
            status: "queued",
            attempts_count: 0,
            queue_position: AiRequest.next_queue_position,
            next_retry_at: nil,
            started_at: nil,
            completed_at: nil,
            last_error_at: nil,
            last_error_kind: nil,
            error_message: nil,
            output_text: nil,
            request_hash: nil,
            response_summary: nil,
            tokens_in: nil,
            tokens_out: nil
          )
        end

        Ai::ReviewJob.perform_later(request.id)
        request
      end

      private

      def handle_failure!(request, error)
        error_kind = classify_error(error)
        attrs = {
          error_message: error.message,
          response_summary: error.message.to_s.truncate(240),
          last_error_at: Time.current,
          last_error_kind: error_kind
        }

        if error_kind == "transient" && request.retryable?
          delay = retry_delay(request.attempts_count)
          request.update!(
            attrs.merge(
              status: "retrying",
              next_retry_at: Time.current + delay,
              completed_at: nil
            )
          )
          {status: :retrying, wait: delay}
        else
          request.update!(
            attrs.merge(
              status: "failed",
              next_retry_at: nil,
              completed_at: Time.current
            )
          )
          {status: :failed, error: error}
        end
      end

      def request_hash(result:, request:)
        Digest::SHA256.hexdigest([result.provider, result.model, request.capability, request.input_text].join(":"))
      end

      def prompt_summary(capability, text)
        "#{capability}: #{text.to_s.truncate(240)}"
      end

      def classify_error(error)
        case error
        when TransientRequestError
          "transient"
        when InvalidCapabilityError
          "validation"
        else
          "permanent"
        end
      end

      def retry_delay(attempts_count)
        [2**attempts_count, 30].min.seconds
      end

      def apply_request_side_effect!(request)
        return unless request.capability == "seed_note"

        Notes::PromiseFulfillmentService.call(ai_request: request)
      end
    end
  end
end
