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
    # correspond to a reachable TentacleSession record. Orphans come
    # from crashes where the record was never persisted, or manual
    # testing outside the normal spawn path.
    #
    # Guarded on three fronts so the sweep does not ever wipe a socket
    # whose child is still live:
    #   1. Skip until bootstrap_sessions! has stamped the sentinel — a
    #      tick that fires before reattach has no idea which records
    #      belong to the incoming process tree.
    #   2. Protect sockets for records in `alive` AND `unknown` (the
    #      latter come from an exception in bootstrap; the child may
    #      still be running and we want the next pass to retry before
    #      we drop its socket on the floor).
    #   3. Inspect the companion `.pid` before rm — if the pid is still
    #      alive, refuse to remove even when the DB has no matching
    #      record (covers spawn→persist races and manual test sockets
    #      belonging to live shells).
    def cleanup_orphaned_sockets
      runtime_dir = ENV.fetch("NEURAMD_TENTACLE_RUNTIME_DIR", Tentacles::DtachWrapper::DEFAULT_RUNTIME_DIR)
      return unless File.directory?(runtime_dir)
      return unless bootstrap_complete?(runtime_dir)

      protected_sockets = TentacleSession
        .where(status: %w[alive unknown])
        .pluck(:dtach_socket)
        .to_set
      Dir.glob(File.join(runtime_dir, "*.sock")).each do |socket_path|
        next if protected_sockets.include?(socket_path)
        next if pid_still_alive?(socket_path)

        remove_orphan(socket_path)
      rescue StandardError => e
        Rails.logger.error("Tentacles::SupervisorJob#cleanup_orphaned_sockets failed for #{socket_path}: #{e.class}: #{e.message}")
      end
    end

    def bootstrap_complete?(runtime_dir)
      File.exist?(File.join(runtime_dir, TentacleRuntime::BOOTSTRAP_SENTINEL))
    end

    def pid_still_alive?(socket_path)
      pid_path = socket_path.sub(/\.sock\z/, ".pid")
      return false unless File.exist?(pid_path)

      raw = File.read(pid_path).strip
      return false if raw.empty?
      pid = Integer(raw)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      # pid exists but is owned by another user — treat as alive so we
      # never delete a socket belonging to a live process we cannot probe.
      true
    rescue ArgumentError, Errno::ENOENT
      false
    end

    def remove_orphan(socket_path)
      FileUtils.rm_f(socket_path)
      pid_path = socket_path.sub(/\.sock\z/, ".pid")
      FileUtils.rm_f(pid_path)
    end
  end
end
