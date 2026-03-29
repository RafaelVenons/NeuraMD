require "digest"
require "uri"
require "zlib"
require_relative "error"
require_relative "provider_registry"

module Ai
  class ReviewService
    CAPABILITIES = %w[rewrite grammar_review translate seed_note].freeze
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
            "provider_base_url" => provider.base_url,
            "model_selection_strategy" => selection[:selection_strategy],
            "model_selection_reason" => selection[:selection_reason]
          }
        )

        Ai::ReviewJob.perform_later(request.id)
        request
      end

      def process_request!(request)
        run_started_at = Time.current

        if serialized_host_request?(request)
          blocking_outcome = nil

          with_execution_slot_lock(request) do
            request.reload
            if request.succeeded? || request.failed? || request.canceled?
              blocking_outcome = request
              next
            end

            blocking_request = blocking_request_for(request, now: run_started_at)
            if blocking_request.present?
              blocking_outcome = {status: :deferred, wait: 1.second}
              next
            end

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

          return blocking_outcome if blocking_outcome.present?
        else
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
        end

        provider = ProviderRegistry.build(request.requested_provider, model_name: request.metadata["requested_model"])
        prompt_text = prompt_input_text(request.capability, request.input_text, provider_name: request.requested_provider)
        result = provider.review(
          capability: normalized_capability(request.capability),
          text: prompt_text,
          language: request.metadata["language"],
          target_language: request.metadata["target_language"]
        )
        normalized_content = normalize_result_content(request, result.content)

        request.update!(
          status: "succeeded",
          provider: result.provider,
          model: result.model,
          request_hash: request_hash(result:, request:),
          response_summary: normalized_content.to_s.truncate(240),
          output_text: normalized_content,
          tokens_in: result.tokens_in,
          tokens_out: result.tokens_out,
          last_error_at: nil,
          last_error_kind: nil,
          next_retry_at: nil,
          completed_at: Time.current
        )
        apply_request_side_effect!(request)
        enqueue_next_request_after!(request)
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

        enqueue_next_request_after!(request)
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
            tokens_out: nil,
            metadata: request.metadata.except("queue_hidden_at")
          )
        end

        Ai::ReviewJob.perform_later(request.id)
        request
      end

      private

      def with_execution_slot_lock(request)
        ApplicationRecord.transaction(requires_new: true) do
          advisory_key = advisory_lock_key_for(request)
          sql = ApplicationRecord.send(:sanitize_sql_array, ["SELECT pg_advisory_xact_lock(?)", advisory_key])
          ApplicationRecord.connection.select_value(sql, "AI execution slot lock")
          yield
        end
      end

      def blocking_request_for(request, now:)
        return nil unless serialized_host_request?(request)

        running_request_for_host(request) || higher_priority_request_for_host(request, now:)
      end

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
          enqueue_next_request_after!(request)
          {status: :failed, error: error}
        end
      end

      def enqueue_next_request_after!(request)
        next_request =
          if serialized_host_request?(request)
            next_request_for_host(request)
          else
            AiRequest.next_ready_request
          end

        return if next_request.blank? || next_request.id == request.id

        Ai::ReviewJob.perform_later(next_request.id)
      end

      def running_request_for_host(request)
        host_scope_for(request)
          .where(status: "running")
          .where.not(id: request.id)
          .first
      end

      def higher_priority_request_for_host(request, now:)
        host_ready_scope_for(request, now:)
          .where.not(id: request.id)
          .queue_order
          .first
          &.then { |candidate| candidate.queue_position < request.queue_position ? candidate : nil }
      end

      def next_request_for_host(request, now: Time.current)
        host_ready_scope_for(request, now:)
          .queue_order
          .first
      end

      def host_scope_for(request)
        AiRequest.where(provider: request.provider)
          .where("metadata ->> 'provider_base_url' = ?", request.metadata["provider_base_url"].to_s)
      end

      def host_ready_scope_for(request, now:)
        host_scope_for(request)
          .where(status: "queued")
          .or(host_scope_for(request).where(status: "retrying").where("next_retry_at IS NULL OR next_retry_at <= ?", now))
      end

      def serialized_host_request?(request)
        %w[ollama local].include?(request.provider)
      end

      def advisory_lock_key_for(request)
        lock_name = "ai-review-slot:#{request.provider}:#{request.metadata["provider_base_url"]}"
        Zlib.crc32(lock_name)
      end

      def request_hash(result:, request:)
        Digest::SHA256.hexdigest([result.provider, result.model, normalized_capability(request.capability), request.input_text].join(":"))
      end

      def prompt_summary(capability, text)
        "#{capability}: #{text.to_s.truncate(240)}"
      end

      def normalized_capability(capability)
        capability.to_s == "suggest" ? "rewrite" : capability.to_s
      end

      def classify_error(error)
        case error
        when TransientRequestError
          "transient"
        when InvalidCapabilityError
          "validation"
        when InvalidOutputError
          "validation"
        else
          "permanent"
        end
      end

      def retry_delay(attempts_count)
        [2**attempts_count, 30].min.seconds
      end

      def apply_request_side_effect!(request)
        nil
      end

      def normalize_result_content(request, content)
        normalized_capability = normalized_capability(request.capability)
        return SeedNoteOutputGuard.normalize!(content:, input_text: request.input_text) if normalized_capability == "seed_note"

        # Google Translate handles wikilinks internally — skip LLM output guards
        return content if request.requested_provider == "google_translate"

        normalized = OutputSanitizer.normalize(content)

        if %w[rewrite grammar_review translate].include?(normalized_capability)
          return WikilinkOutputGuard.normalize!(content: normalized, source_text: request.input_text)
        end

        normalized
      end

      def prompt_input_text(capability, text, provider_name: nil)
        return text if normalized_capability(capability) == "seed_note"
        return text if provider_name == "google_translate"

        WikilinkPromptText.normalize(text)
      end
    end
  end
end
