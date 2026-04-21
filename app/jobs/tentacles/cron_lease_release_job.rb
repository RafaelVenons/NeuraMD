module Tentacles
  class CronLeaseReleaseJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 10
    retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 10

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(note_id:, lease_token:, transcript:, command:, started_at:, ended_at:, exit_status:)
      note = Note.find(note_id)
      success = false

      ActiveRecord::Base.transaction do
        persisted = persist_transcript(
          note: note,
          transcript: transcript,
          command: command,
          started_at: parse_time(started_at),
          ended_at: parse_time(ended_at)
        )
        success = persisted && exit_status == 0
        apply_cleanup(note_id: note_id, lease_token: lease_token, success: success)
      end

      return if success
      Rails.logger.warn(
        "Tentacles::CronLeaseReleaseJob run for note #{note_id} not successful " \
        "(exit_status=#{exit_status.inspect}); lease cleared, retry on next tick"
      )
    end

    private

    def persist_transcript(note:, transcript:, command:, started_at:, ended_at:)
      Tentacles::TranscriptService.persist(
        note: note, transcript: transcript, command: command,
        started_at: started_at, ended_at: ended_at, author: nil
      )
      true
    rescue StandardError => e
      Rails.logger.error(
        "Tentacles::CronLeaseReleaseJob transcript persist failed for note #{note.id}: #{e.class}: #{e.message}"
      )
      false
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
