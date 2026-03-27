require_relative "../../services/mfa/error"

module Tts
  class GenerateJob < ApplicationJob
    queue_as :airch

    discard_on ActiveJob::DeserializationError

    def perform(ai_request_id)
      request = AiRequest.find(ai_request_id)
      return if request.canceled?

      request.update!(
        status: "running",
        started_at: request.started_at || Time.current,
        attempts_count: request.attempts_count + 1
      )

      provider = ProviderRegistry.build(request.provider)
      meta = request.metadata

      result = provider.synthesize(
        text: request.input_text,
        voice: meta["voice"],
        language: meta["language"],
        model: request.model,
        format: meta["format"] || "mp3",
        settings: meta["settings"] || {}
      )

      tts_asset = NoteTtsAsset.find(meta["tts_asset_id"])
      format_ext = meta["format"] || "mp3"
      tts_asset.audio.attach(
        io: StringIO.new(result.audio_data),
        filename: "tts_#{tts_asset.id}.#{format_ext}",
        content_type: result.content_type
      )
      tts_asset.update!(duration_ms: result.duration_ms) if result.duration_ms

      # Run MFA alignment synchronously — audio + alignment delivered together
      run_mfa_alignment(tts_asset)

      request.update!(
        status: "succeeded",
        completed_at: Time.current,
        error_message: nil,
        last_error_at: nil,
        last_error_kind: nil
      )
    rescue Tts::TransientRequestError => e
      handle_transient_error!(request, e)
    rescue Tts::RequestError => e
      handle_permanent_error!(request, e)
    rescue Tts::Error => e
      handle_permanent_error!(request, e)
    end

    private

    def run_mfa_alignment(tts_asset)
      tts_asset.update!(alignment_status: "pending")
      Mfa::AlignService.call(tts_asset)
    rescue Mfa::Error => e
      # MFA failure is non-fatal — audio is still usable without alignment
      tts_asset.update!(alignment_status: "failed")
      Rails.logger.warn("MFA alignment failed for asset #{tts_asset.id}: #{e.message}")
    end

    def handle_transient_error!(request, error)
      if request.retryable?
        wait_time = [2**request.attempts_count, 30].min.seconds
        request.update!(
          status: "retrying",
          error_message: error.message,
          last_error_at: Time.current,
          last_error_kind: "transient",
          next_retry_at: Time.current + wait_time
        )
        self.class.set(wait: wait_time).perform_later(request.id)
      else
        handle_permanent_error!(request, error)
      end
    end

    def handle_permanent_error!(request, error)
      request.update!(
        status: "failed",
        error_message: error.message,
        last_error_at: Time.current,
        last_error_kind: "permanent",
        completed_at: Time.current
      )
    end
  end
end
