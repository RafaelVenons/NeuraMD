module Tentacles
  class CronLeaseReleaseJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 10
    retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 10

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(note_id:, lease_token:, transcript:, command:, started_at:, ended_at:, exit_status:)
      note = Note.find(note_id)
      child_succeeded = exit_status == 0
      success = false
      rows_updated = 0
      transcript_error = nil

      ActiveRecord::Base.transaction do
        transcript_error = run_persist(
          note: note,
          transcript: transcript,
          command: command,
          started_at: parse_time(started_at),
          ended_at: parse_time(ended_at)
        )
        success = child_succeeded
        rows_updated = apply_cleanup(note_id: note_id, lease_token: lease_token, success: success)
      end

      if success && transcript_error
        Rails.logger.error(
          "Tentacles::CronLeaseReleaseJob advancing last_fired_at without transcript for note #{note_id} " \
          "(#{transcript_error.class}: #{transcript_error.message}); child succeeded, not re-executing"
        )
      end

      if success && rows_updated.zero?
        Rails.logger.warn(
          "Tentacles::CronLeaseReleaseJob stale release for note #{note_id} " \
          "(lease_token no longer matches — row reclaimed by newer tick); " \
          "transcript persisted, last_fired_at not advanced"
        )
        return
      end

      return if success

      if transcript_error
        transcript_bytes = transcript.to_s.b
        Rails.logger.error(
          "Tentacles::CronLeaseReleaseJob run for note #{note_id} not successful " \
          "(exit_status=#{exit_status.inspect}) AND transcript persist failed " \
          "(#{transcript_error.class}: #{transcript_error.message}); lease cleared, retry on next tick. " \
          "Transcript metadata: bytesize=#{transcript_bytes.bytesize} " \
          "sha256=#{Digest::SHA256.hexdigest(transcript_bytes)}"
        )
      else
        Rails.logger.warn(
          "Tentacles::CronLeaseReleaseJob run for note #{note_id} not successful " \
          "(exit_status=#{exit_status.inspect}); lease cleared, retry on next tick"
        )
      end
    end

    private

    def run_persist(note:, transcript:, command:, started_at:, ended_at:)
      ActiveRecord::Base.transaction(requires_new: true) do
        Tentacles::TranscriptService.persist(
          note: note, transcript: transcript, command: command,
          started_at: started_at, ended_at: ended_at, author: nil
        )
      end
      nil
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      raise
    rescue StandardError => e
      Rails.logger.error(
        "Tentacles::CronLeaseReleaseJob transcript persist failed for note #{note.id}: #{e.class}: #{e.message}"
      )
      e
    end

    def apply_cleanup(note_id:, lease_token:, success:)
      updates = { last_attempted_at: nil, lease_pid: nil, lease_host: nil, lease_token: nil }
      updates[:last_fired_at] = Time.current if success
      TentacleCronState
        .where(note_id: note_id, lease_token: lease_token)
        .update_all(updates)
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      Time.iso8601(value.to_s)
    end
  end
end
