class TentacleRuntime
  # Descriptor-driven on_exit reconstruction. When a caller passes
  # `persistence:` to TentacleRuntime.start, the descriptor is stored on
  # the TentacleSession record's `metadata` column. On reattach after a
  # Puma restart, bootstrap_sessions! reads the descriptor back and
  # builds an equivalent on_exit closure — without it the transcript of
  # any detached session that exits naturally after a deploy would be
  # dropped, because the original closure lived only in the old process.
  #
  # Three kinds are supported today:
  #   {kind: "web",  author_id: <Integer|nil>} — human-initiated via UI
  #   {kind: "cron", lease_token: <String>}    — scheduled by Tentacles::CronTickJob
  #   {kind: "s2s"}                            — agent-initiated via
  #     /api/s2s/tentacles/:slug/activate. Transcript persistence
  #     follows the same path as web (no human author), cron-specific
  #     lease dance is skipped.
  module Persistence
    KINDS = %w[web cron s2s].freeze

    def self.validate!(descriptor)
      return nil if descriptor.nil?

      normalized = descriptor.transform_keys(&:to_s)
      kind = normalized["kind"].to_s
      raise ArgumentError, "persistence kind is required" if kind.empty?
      raise ArgumentError, "unknown persistence kind: #{kind}" unless KINDS.include?(kind)

      normalized
    end

    def self.build_on_exit(descriptor, tentacle_id:)
      return nil if descriptor.nil?

      normalized = descriptor.transform_keys(&:to_s)
      case normalized["kind"]
      when "web", "s2s" then build_web(normalized, tentacle_id: tentacle_id)
      when "cron"       then build_cron(normalized, tentacle_id: tentacle_id)
      end
    end

    def self.build_web(descriptor, tentacle_id:)
      author_id = descriptor["author_id"]
      note_id = tentacle_id
      ->(transcript:, command:, started_at:, ended_at:, **) do
        note = Note.find_by(id: note_id)
        return unless note

        author = author_id ? User.find_by(id: author_id) : nil
        Tentacles::TranscriptService.persist(
          note: note,
          transcript: transcript,
          command: command,
          started_at: started_at,
          ended_at: ended_at,
          author: author
        )
      end
    end

    def self.build_cron(descriptor, tentacle_id:)
      lease_token = descriptor["lease_token"]
      note_id = tentacle_id
      ->(transcript:, command:, started_at:, ended_at:, exit_status: nil, **) do
        Tentacles::CronLeaseReleaseJob.perform_later(
          note_id: note_id,
          lease_token: lease_token,
          transcript: transcript.to_s,
          command: Array(command),
          started_at: format_time(started_at),
          ended_at: format_time(ended_at),
          exit_status: exit_status
        )
      rescue StandardError => e
        Tentacles::CronTickJob.new.emergency_release_on_enqueue_failure(
          note_id: note_id, lease_token: lease_token, error: e
        )
      end
    end

    def self.format_time(value)
      return value.iso8601(6) if value.respond_to?(:iso8601)
      Time.current.iso8601(6)
    end
  end
end
