require "set"

module Tentacles
  class SupervisorJob < ApplicationJob
    queue_as :default

    GRACE_PERIOD = 5.seconds
    DB_SCAN_THRESHOLD = 5.minutes

    def perform
      reap_in_memory_sessions
      return unless TentacleRuntime.dtach_enabled?

      reap_stale_db_sessions
      cleanup_orphaned_sockets
    end

    private

    # Original path — walks the in-memory SESSIONS map for entries whose
    # process has died but were never cleaned up (e.g. a reader thread
    # crashed before firing on_exit). Preserves the legacy behaviour
    # unchanged.
    def reap_in_memory_sessions
      cutoff = Time.current - GRACE_PERIOD
      TentacleRuntime::SESSIONS.each_pair do |tentacle_id, session|
        next unless session
        next if session.alive?
        next if session.started_at && session.started_at > cutoff

        reap(tentacle_id)
      end
    end

    def reap(tentacle_id)
      TentacleRuntime.stop(tentacle_id: tentacle_id)
    rescue StandardError => e
      Rails.logger.error("Tentacles::SupervisorJob failed to reap #{tentacle_id}: #{e.class}: #{e.message}")
    end

    # dtach-only path — inspects TentacleSession records whose last_seen_at
    # is older than the scan threshold and checks the detached child via
    # DtachWrapper. Alive → touch_seen! and move on; dead → mark_ended!
    # and clean up the dtach socket/pidfile so the orphaned-sockets sweep
    # does not trip over it.
    def reap_stale_db_sessions
      threshold = DB_SCAN_THRESHOLD.ago
      scope = TentacleSession.alive.where("last_seen_at IS NULL OR last_seen_at < ?", threshold)
      scope.find_each do |record|
        handle_stale_record(record)
      rescue StandardError => e
        Rails.logger.error("Tentacles::SupervisorJob#reap_stale_db_sessions failed for #{record.id}: #{e.class}: #{e.message}")
      end
    end

    def handle_stale_record(record)
      wrapper = Tentacles::DtachWrapper.new(
        session_id: record.tentacle_note_id,
        runtime_dir: File.dirname(record.dtach_socket)
      )

      if wrapper.alive?
        record.touch_seen!
        return
      end

      reason = wrapper.socket_exists? ? "crash" : "missing_pid"
      record.mark_ended!(reason: reason)
      wrapper.cleanup
    end

    # Sweeps the dtach runtime directory for `.sock` files that do not
    # correspond to a live TentacleSession record. Orphans come from
    # crashes where the record was never persisted, or manual testing
    # outside the normal spawn path. Leaving them around would let a
    # future spawn with the same session_id collide with a stale socket.
    def cleanup_orphaned_sockets
      runtime_dir = ENV.fetch("NEURAMD_TENTACLE_RUNTIME_DIR", Tentacles::DtachWrapper::DEFAULT_RUNTIME_DIR)
      return unless File.directory?(runtime_dir)

      known_sockets = TentacleSession.alive.pluck(:dtach_socket).to_set
      Dir.glob(File.join(runtime_dir, "*.sock")).each do |socket_path|
        next if known_sockets.include?(socket_path)

        remove_orphan(socket_path)
      rescue StandardError => e
        Rails.logger.error("Tentacles::SupervisorJob#cleanup_orphaned_sockets failed for #{socket_path}: #{e.class}: #{e.message}")
      end
    end

    def remove_orphan(socket_path)
      FileUtils.rm_f(socket_path)
      pid_path = socket_path.sub(/\.sock\z/, ".pid")
      FileUtils.rm_f(pid_path)
    end
  end
end
