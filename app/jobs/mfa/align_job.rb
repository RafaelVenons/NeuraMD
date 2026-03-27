require_relative "../../services/mfa/error"

module Mfa
  class AlignJob < ApplicationJob
    queue_as :airch

    discard_on ActiveJob::DeserializationError

    retry_on Mfa::TransientError, wait: :polynomially_longer, attempts: 3

    def perform(tts_asset_id)
      asset = NoteTtsAsset.find(tts_asset_id)
      return unless asset.audio.attached?
      return if asset.alignment_status == "succeeded"

      asset.update!(alignment_status: "pending") unless asset.alignment_pending?

      Mfa::AlignService.call(asset)
    rescue Mfa::TransientError
      raise # Let retry_on handle it
    rescue Mfa::Error => e
      asset.update!(alignment_status: "failed") if asset.persisted?
      Rails.logger.error("MFA alignment failed for asset #{tts_asset_id}: #{e.message}")
    end
  end
end
