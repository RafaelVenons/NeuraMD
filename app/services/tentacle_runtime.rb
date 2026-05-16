require "pty"
require "socket"
require "concurrent/map"
require "neuramd/metrics"

class TentacleRuntime
  SESSIONS = Concurrent::Map.new
  # Per-tentacle-id mutex table. Serializes start() for the same id so
  # two concurrent callers cannot both race past the SESSIONS liveness
  # check, double-spawn a dtach child, and have one clobber the other
  # through the persist-failure cleanup path.
  START_MUTEXES = Concurrent::Map.new
  INITIAL_PROMPT_BOOT_DELAY = 1.5
  # After first PTY output (banner / TUI splash), wait for output to be
  # quiet for this many seconds before writing the prompt. Without it
  # we race the Claude Code TUI: bytes written between the splash and
  # the readline prompt being up are eaten by the early state, never
  # reaching the agent. 3/3 ocorrências do bug initial_prompt
  # observadas em 17h de campo (2026-04-23/24) seguiam esse padrão.
  INITIAL_PROMPT_QUIET_GRACE = 0.8
  INITIAL_PROMPT_QUIET_MAX_WAIT = 15.0
  # Best-effort fallback when wait_for_quiet times out but boot succeeded.
  # Empirically (2026-05-09 sentinela wake at 23:02:00) Claude Code TUI
  # never settles into 0.8s of contiguous quiet within 15s — splash,
  # animations, and cursor blink keep the stream warm. Bumping max_wait
  # higher just postpones the same false. After the first output is
  # observed, the readline buffer is up; sleeping a bounded extra delay
  # then writing best-effort is reliable in practice (matches what a
  # human typing into the TUI does at any moment). Original quiet gate
  # is preserved as the happy path; this only fires when it gives up.
  INITIAL_PROMPT_BEST_EFFORT_DELAY = 5.0
  # Heartbeat that touches TentacleSession#last_seen_at while a session
  # is alive, so a stale owner (host crashed or never returned) can be
  # reaped cross-host instead of wedging the per-note alive uniqueness
  # index forever. Interval ~30s; reap threshold a few intervals out.
  HEARTBEAT_INTERVAL = 30.0
  # Fencing lease for the session row. Heartbeat renews lease_expires_at
  # via CAS on lease_token; cross-host reap is also CAS-conditioned on
  # the observed token+expiry, so an owner that renews between read
  # and update wins the race. 5min keeps failover prompt — with the
  # CAS guard on both renew and reap, a brief owner stall just hits
  # one missed heartbeat (resumes cleanly on next tick); a host that
  # actually died is reclaimed in bounded time.
  LEASE_DURATION = 5.minutes
  HEARTBEAT_STALE_TTL = 5.minutes
  # Marker file written under NEURAMD_TENTACLE_RUNTIME_DIR once
  # bootstrap_sessions! has finished a pass. SupervisorJob only sweeps
  # orphan sockets after this file exists so a tick that fires before
  # reattach cannot wipe live sockets.
  BOOTSTRAP_SENTINEL = ".bootstrap_complete".freeze

  # Raised when spawn_via_dtach finds a live dtach socket/pidfile on
  # disk but no TentacleSession record vouches for it. We refuse to
  # attach because a later stop/drain would signal whatever pid the
  # stale pidfile points at — potentially an unrelated process.
  class OrphanSocketError < StandardError; end

  # Raised when an alive TentacleSession record exists but its stored
  # identity (dtach_socket path or command) does not match what the
  # current start() call is requesting. Refuses to attach so a caller
  # asking for command B does not end up steering (and later killing)
  # a process that was spawned for command A.
  class OwnershipMismatchError < StandardError; end

  # Raised when a PTY-mode spawn loses the per-note alive uniqueness
  # race — another web process already owns a live session for this
  # note. The session map is process-local, so this process cannot
  # see or steer that session; it refuses to spawn a duplicate (which
  # would run two runtimes against the same inbox/worktree) and the
  # orphan child from the lost race is killed before raising.
  class ForeignOwnedSession < StandardError; end

  class << self
    # Whether the detached (dtach) backend is enabled. When false the
    # runtime keeps the legacy PTY.spawn path, so flipping this on/off
    # is a reversible switch with no migration.
    def dtach_enabled?
      ENV["NEURAMD_FEATURE_DTACH"].to_s.downcase == "on"
    end

    def start(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil, persistence: nil,
              initial_prompt: nil, context_warning_ratio: nil, context_window_tokens: nil,
              repo_root_fingerprint: nil, note_slug: nil)
      existing = SESSIONS[tentacle_id]
      return existing if existing&.alive?

      START_MUTEXES.compute_if_absent(tentacle_id) { Mutex.new }.synchronize do
        existing = SESSIONS[tentacle_id]
        return existing if existing&.alive?

        FileUtils.mkdir_p(cwd) if cwd
        descriptor = Persistence.validate!(persistence)
        effective_on_exit =
          if descriptor
            Persistence.build_on_exit(descriptor, tentacle_id: tentacle_id)
          else
            on_exit
          end

        session = Session.new(
          tentacle_id: tentacle_id,
          command: Array(command),
          cwd: cwd,
          env: env,
          on_exit: effective_on_exit,
          persistence_descriptor: descriptor,
          context_warning_ratio: context_warning_ratio,
          context_window_tokens: context_window_tokens,
          repo_root_fingerprint: repo_root_fingerprint,
          note_slug: note_slug
        )
        SESSIONS[tentacle_id] = session
        deliver_initial_prompt(session, initial_prompt) if initial_prompt.present?
        Neuramd::Metrics.emit("tentacle_spawn", {tentacle_id: tentacle_id.to_s, command: Array(command).first})
        session
      end
    end

    private

    # Synchronous delivery of the initial_prompt to the session's PTY.
    # Two-phase confirmation so the prompt actually lands inside Claude
    # Code's readline buffer instead of getting eaten by the splash/TUI
    # init:
    #   1. wait_for_first_output must report `true` — PTY produced
    #      something (banner / TUI start). A `false` return means the
    #      PTY never booted in time, so the `write` would race a
    #      pre-readline buffer; skip both write and mark.
    #   2. wait_for_quiet must report `true` — the stream observed
    #      output and went quiet for QUIET_GRACE seconds (capped at
    #      QUIET_MAX_WAIT). A `false` return means the TUI never
    #      finished drawing inside the budget; the prompt would still
    #      race the early-state buffer, so skip mark even though the
    #      first phase booted.
    # Only when both phases confirm do we write and flip
    # session#initial_prompt_delivered? to true. SessionControl reads
    # that flag to populate routed_prompt_delivered honestly: callers
    # that see `false` know the prompt was NOT delivered and can
    # retry via the alive-session reuse path. Errors are logged and
    # swallowed — a slow PTY must not break the activate API call.
    def deliver_initial_prompt(session, prompt)
      unless session.wait_for_first_output(timeout: INITIAL_PROMPT_BOOT_DELAY)
        Rails.logger.warn(
          "TentacleRuntime initial_prompt skipped for #{session.tentacle_id}: " \
          "PTY produced no output within #{INITIAL_PROMPT_BOOT_DELAY}s; leaving routed_prompt_delivered=false"
        )
        return
      end
      unless session.wait_for_quiet(grace: INITIAL_PROMPT_QUIET_GRACE, max_wait: INITIAL_PROMPT_QUIET_MAX_WAIT)
        Rails.logger.warn(
          "TentacleRuntime initial_prompt best-effort fallback for #{session.tentacle_id}: " \
          "PTY output never quieted within #{INITIAL_PROMPT_QUIET_MAX_WAIT}s; " \
          "sleeping #{INITIAL_PROMPT_BEST_EFFORT_DELAY}s then writing anyway " \
          "(boot succeeded, readline assumed up)"
        )
        sleep INITIAL_PROMPT_BEST_EFFORT_DELAY
      end
      # `session.submit_sequence` returns the right Enter encoding for
      # the spawned command — `\e[13u` (CSI Kitty keyboard) for claude,
      # plain `\r` for bash. Sending the wrong one leaves the prompt
      # visible but unsubmitted (claude TUI treats `\r` as literal
      # newline text after enabling the Kitty protocol). Diagnosed
      # empirically 2026-04-27 against a live gerente session.
      # Session#write returns false on EIO/IOError — a fresh PTY that
      # dies between spawn and this write must not be reported as a
      # successful delivery. Only mark when the write confirmed.
      if session.write("#{prompt}#{session.submit_sequence}")
        session.mark_initial_prompt_delivered!
      else
        Rails.logger.warn(
          "TentacleRuntime initial_prompt write failed for #{session.tentacle_id}: " \
          "PTY channel closed before delivery; leaving initial_prompt_delivered=false"
        )
      end
    rescue StandardError => e
      Rails.logger.error("TentacleRuntime initial_prompt failed: #{e.class}: #{e.message}")
    end

    public

    def write(tentacle_id:, data:)
      SESSIONS[tentacle_id]&.write(data)
    end

    def resize(tentacle_id:, cols:, rows:)
      SESSIONS[tentacle_id]&.resize(cols: cols, rows: rows)
    end

    # Stops a tentacle session and removes it from the in-memory map.
    # `grace` is forwarded to Session#stop and bounds the SIGTERM window
    # before SIGKILL escalation. Default preserves the legacy 0.5s
    # behaviour; SessionControl.terminate(force: true) passes 0 to skip
    # the wait and go straight to KILL. Returns the Session that was
    # stopped (or nil when the map had no entry).
    def stop(tentacle_id:, grace: 0.5)
      session = SESSIONS.delete(tentacle_id)
      session&.stop(grace: grace)
      session
    end

    def get(tentacle_id)
      SESSIONS[tentacle_id]
    end

    # Cross-process session lookup. On a local SESSIONS miss, a session
    # spawned by another web process is invisible to this one — but a
    # dtach-backed session is reachable through its shared runtime
    # socket. When dtach is enabled and an alive TentacleSession record
    # for this note carries a socket, reattach to it so this process can
    # reuse/control it (the cross-process path SessionControl needs for
    # activate + terminate under multiple web workers).
    #
    # Returns nil — leaving the caller to fall through to spawn — for a
    # local miss with no record, a PTY-mode record (no socket, genuinely
    # unreachable from another process), or when dtach is disabled.
    def get_or_reattach(tentacle_id)
      existing = SESSIONS[tentacle_id]
      return existing if existing
      return nil unless dtach_enabled?

      record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
      return nil if record.nil? || record.dtach_socket.blank?

      START_MUTEXES.compute_if_absent(tentacle_id) { Mutex.new }.synchronize do
        already = SESSIONS[tentacle_id]
        next already if already

        reattach_record(record)
      end
    rescue StandardError => e
      Rails.logger.error(
        "[tentacle_runtime] get_or_reattach failed for #{tentacle_id}: #{e.class}: #{e.message}"
      )
      nil
    end

    # Graceful group stop used by shutdown hooks and the drain endpoint.
    # Each session fires its on_exit callback exactly once (persisting the
    # transcript) before the PTY is closed. If a child ignores SIGTERM, we
    # escalate to SIGKILL after the grace window.
    #
    # Returns the list of tentacle_ids that were stopped, as strings.
    def graceful_stop_all(grace: 10)
      stopped = []
      SESSIONS.each_pair do |id, session|
        next unless session
        begin
          session.stop(grace: grace)
        rescue StandardError => e
          Rails.logger.error("TentacleRuntime#graceful_stop_all failed for #{id}: #{e.class}: #{e.message}")
        end
        stopped << id.to_s
      end
      SESSIONS.clear
      stopped
    end

    # Soft shutdown path for dtach mode — disconnects every live
    # attach proxy without killing the detached children. The children
    # keep running under their dtach sessions; bootstrap_sessions! will
    # reattach them on the next boot.
    #
    # Returns the list of tentacle_ids that were detached, as strings.
    def detach_all_for_shutdown
      detached = []
      SESSIONS.each_pair do |id, session|
        next unless session
        begin
          session.stop(detach_only: true)
        rescue StandardError => e
          Rails.logger.error("TentacleRuntime#detach_all_for_shutdown failed for #{id}: #{e.class}: #{e.message}")
        end
        detached << id.to_s
      end
      SESSIONS.clear
      detached
    end

    # Route shutdown requests to the right path. Puma's `on_restart`
    # and the `at_exit` initializer both call this; it picks detach
    # when the dtach backend is live so deploys stop killing sessions.
    def shutdown!(grace: 10)
      if dtach_enabled?
        detach_all_for_shutdown
      else
        graceful_stop_all(grace: grace)
      end
    end

    # Scan TentacleSession records and reattach to each detached child
    # that is still alive. Records whose child is provably dead are
    # finalized to `exited` with the right reason (missing_pid/crash)
    # and their dtach socket/pidfile are cleaned up in the same pass.
    # Records whose reattach raised unexpectedly stay in `unknown` so
    # the next SupervisorJob tick can retry.
    #
    # Writes BOOTSTRAP_SENTINEL under the runtime dir at the end so
    # SupervisorJob#cleanup_orphaned_sockets knows it can safely sweep.
    #
    # Called from config/initializers/tentacle_runtime_bootstrap.rb on
    # Rails boot. Always reaps orphaned PTY-mode records for this host;
    # dtach reattach runs only when the dtach backend is enabled.
    def bootstrap_sessions!
      reaped = reap_orphaned_pty_records!
      return reaped unless dtach_enabled?

      reattached = 0
      TentacleSession.alive.find_each do |record|
        # PTY-mode records (no socket) are handled by the reap pass
        # above — they cannot be reattached, only finalized.
        next if record.dtach_socket.blank?

        begin
          if reattach_record(record)
            reattached += 1
          else
            finalize_dead_record(record)
          end
        rescue StandardError => e
          Rails.logger.error("[tentacle_runtime] reattach failed for #{record.tentacle_note_id}: #{e.class}: #{e.message}")
          begin
            record.mark_unknown!
          rescue StandardError
            # best effort
          end
        end
      end
      mark_bootstrap_complete!
      reattached
    end

    # Writes a sentinel file so SupervisorJob can tell that bootstrap
    # finished at least one pass. Stored under the runtime dir (tmpfs
    # in production) so it wipes on reboot along with the sockets.
    def mark_bootstrap_complete!
      runtime_dir = ENV.fetch("NEURAMD_TENTACLE_RUNTIME_DIR", Tentacles::DtachWrapper::DEFAULT_RUNTIME_DIR)
      FileUtils.mkdir_p(runtime_dir)
      FileUtils.touch(File.join(runtime_dir, BOOTSTRAP_SENTINEL))
    rescue StandardError => e
      Rails.logger.error("[tentacle_runtime] failed to write bootstrap sentinel: #{e.class}: #{e.message}")
    end

    def reset!
      SESSIONS.each_value do |session|
        session.stop
      rescue StandardError
        # best-effort teardown for specs
      end
      SESSIONS.clear
      START_MUTEXES.clear
    end

    private

    # Finalizes PTY-mode TentacleSession records this host owns whose
    # process is gone. A PTY child dies with its Puma worker (PTY master
    # close → SIGHUP), so on a fresh boot any alive PTY record for this
    # host with a dead pid is an orphan from a crashed/restarted worker
    # whose reader-thread on_exit never ran. dtach-backed records carry
    # a socket and are reattached separately, so they are skipped here.
    # Scoped by host because a pid is only meaningful on its own host.
    def reap_orphaned_pty_records!
      host = Socket.gethostname
      reaped = 0
      TentacleSession.alive.where(dtach_socket: nil).find_each do |record|
        if record.host == host
          # Same host: bootstrap only runs at process boot, and at that
          # point SESSIONS is empty — any alive record for this host
          # predates this worker by definition. The previous PID check
          # was unsafe under PID reuse (kill(0, pid) can find an
          # unrelated process that happens to have the same id), which
          # would leave the row alive forever and wedge the per-note
          # unique index. Reap unconditionally on same-host bootstrap.
        else
          # Different host: we cannot probe a foreign pid, so use the
          # fencing lease. Only an EXPIRED lease is unambiguous evidence
          # of a dead owner — a stale timestamp alone could mis-fence a
          # briefly stalled-but-alive owner. Records without a lease
          # (legacy or pre-this-PR) are left alone for operator review.
          next unless record.lease_expires_at && record.lease_expires_at < Time.current

          # CAS reclaim: the conditional UPDATE must still see the same
          # token AND an expired lease. If the owner renewed between our
          # read above and this write, the WHERE matches 0 rows and we
          # leave the live session alone (Codex finding: reap was not
          # CAS-safe and could false-fence a live owner).
          rows = TentacleSession
            .where(id: record.id, lease_token: record.lease_token)
            .where("lease_expires_at < ?", Time.current)
            .update_all(
              status: "exited",
              ended_at: Time.current,
              exit_reason: "missing_pid",
              lease_token: SecureRandom.uuid,
              updated_at: Time.current
            )
          reaped += 1 if rows.positive?
          next
        end

        # Same-host reap path (pid dead): no CAS needed — we own the
        # host and no foreign owner can renew. Rotate the token so any
        # late-waking stale owner self-fences on its next heartbeat.
        record.update!(
          status: "exited",
          ended_at: Time.current,
          exit_reason: "missing_pid",
          lease_token: SecureRandom.uuid
        )
        reaped += 1
      rescue StandardError => e
        Rails.logger.error(
          "[tentacle_runtime] failed to reap orphaned PTY record #{record.id}: #{e.class}: #{e.message}"
        )
      end
      reaped
    end

    def process_pid_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # Transition a known-dead session record out of `alive`: stamp
    # status=exited with the matching reason (socket_exists → "crash",
    # otherwise "missing_pid") and drop the socket/pidfile from disk.
    def finalize_dead_record(record)
      wrapper = Tentacles::DtachWrapper.new(
        session_id: record.tentacle_note_id,
        runtime_dir: File.dirname(record.dtach_socket)
      )
      reason = wrapper.socket_exists? ? "crash" : "missing_pid"
      record.mark_ended!(reason: reason)
      wrapper.cleanup
    end

    # Returns the reattached Session on success, nil when the record is
    # stale (dead pid or missing socket). Caller handles the stale path.
    def reattach_record(record)
      runtime_dir = File.dirname(record.dtach_socket)
      wrapper = Tentacles::DtachWrapper.new(
        session_id: record.tentacle_note_id,
        runtime_dir: runtime_dir
      )
      return nil unless wrapper.socket_exists?
      return nil unless wrapper.alive?

      command = Shellwords.split(record.command.to_s)
      command = [record.command.to_s] if command.empty?

      metadata = record.metadata.is_a?(Hash) ? record.metadata : {}
      descriptor = metadata["persistence"]
      reconstructed_on_exit =
        if descriptor
          Persistence.build_on_exit(descriptor, tentacle_id: record.tentacle_note_id)
        end

      # "Key absent" means the record was written before
      # persist_tentacle_session_record! started always-writing the
      # fingerprint key. Such records cannot be identity-verified, but
      # they must not be stranded on deploy — the legacy flag tells
      # SessionControl#assert_session_fresh! to log + allow reuse
      # instead of rejecting them as unverifiable. Post-fix records
      # always carry the key (possibly with a nil value), so a true
      # nil there is genuine and still triggers fail-closed.
      pre_persistence = !metadata.key?("repo_root_fingerprint")

      session = Session.new(
        tentacle_id: record.tentacle_note_id,
        command: command,
        cwd: record.cwd,
        session_record: record,
        on_exit: reconstructed_on_exit,
        repo_root_fingerprint: metadata["repo_root_fingerprint"],
        pre_persistence_fingerprint: pre_persistence
      )
      SESSIONS[record.tentacle_note_id] = session
      record.touch_seen!
      session
    end
  end

  class Session
    # Scrub Rails-specific vars inherited from the parent process. In dev,
    # a child shell running `bundle exec rspec` must not inherit
    # RAILS_ENV=development — DatabaseCleaner would truncate the dev DB. In
    # production the opposite is needed: the child (e.g. bin/mcp-server) has
    # to see RAILS_ENV=production, otherwise it falls back to development and
    # tries to load dev-only gems missing from the production bundle.
    def self.default_env
      rails_env = Rails.env.production? ? "production" : nil
      {
        "TERM" => "xterm-256color",
        "LANG" => ENV["LANG"] || "en_US.UTF-8",
        "RAILS_ENV" => rails_env,
        "RACK_ENV" => rails_env,
        "DATABASE_URL" => nil,
        "BUNDLE_GEMFILE" => nil
      }
    end
    LIVE_TRANSCRIPT_CAP = 200_000
    DEFAULT_CONTEXT_WINDOW_TOKENS = 200_000
    DEFAULT_CONTEXT_WARNING_RATIO = 0.70
    TOKEN_BYTES_RATIO = 4

    attr_reader :tentacle_id, :pid, :started_at, :dtach, :cwd, :repo_root_fingerprint, :note_slug

    def initialize(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil,
                   context_warning_ratio: nil, context_window_tokens: nil,
                   session_record: nil, persistence_descriptor: nil,
                   repo_root_fingerprint: nil, note_slug: nil,
                   pre_persistence_fingerprint: false)
      @tentacle_id = tentacle_id
      @command = command
      @cwd = cwd
      @repo_root_fingerprint = repo_root_fingerprint
      @pre_persistence_fingerprint = pre_persistence_fingerprint
      @note_slug = note_slug.presence
      @env = build_child_env(env, tentacle_id, @note_slug)
      @on_exit = on_exit
      @persistence_descriptor = persistence_descriptor
      @transcript = +""
      @transcript_mutex = Mutex.new
      @transcript_dropped_bytes = 0
      @on_exit_fired = false
      @on_exit_mutex = Mutex.new
      @boot_mutex = Mutex.new
      @boot_cv = ConditionVariable.new
      @booted = false
      @last_output_at = nil
      @initial_prompt_delivered = false
      @context_warning_ratio = (context_warning_ratio || DEFAULT_CONTEXT_WARNING_RATIO).to_f
      @context_window_tokens = (context_window_tokens || DEFAULT_CONTEXT_WINDOW_TOKENS).to_i
      @context_warning_fired = false
      @context_warning_mutex = Mutex.new
      @last_wake_nudge_at = nil
      @wake_nudge_mutex = Mutex.new
      @started_at = session_record&.started_at || Time.current
      @dtach = nil
      @attach_pid = nil
      @session_record = session_record
      @heartbeat_thread = nil
      spawn_process
      start_reader
      start_heartbeat
    end

    # Identity grounding for the spawned tentacle — env vars an agent
    # can read the moment it boots, independent of any initial_prompt
    # that may or may not have made it through the PTY race window.
    # Without these, an agent woken by activate_tentacle_session whose
    # prompt got eaten cannot distinguish itself from any other slug
    # the human happens to mention next, and starts answering on behalf
    # of the wrong agent (cross-slug confusion incident, 2026-04-23).
    def build_child_env(extra_env, tentacle_id, slug)
      base = self.class.default_env.merge(extra_env)
      base["NEURAMD_TENTACLE_ID"] = tentacle_id.to_s
      base["NEURAMD_AGENT_UUID"] = tentacle_id.to_s
      base["NEURAMD_AGENT_SLUG"] = slug if slug
      base
    end

    def dtach_mode?
      !@dtach.nil?
    end

    # Returns true when the PTY produced output (banner / TUI start)
    # within the timeout, false when the timeout elapsed first. Callers
    # use this as a hard gate before writing the initial prompt: a
    # `false` return means the PTY hasn't reached its readline buffer
    # yet, so any write would be eaten by the early state.
    def wait_for_first_output(timeout:)
      @boot_mutex.synchronize do
        return true if @booted
        @boot_cv.wait(@boot_mutex, timeout)
        @booted
      end
    end

    # Wait until the output stream has been silent for `grace` seconds,
    # capped by `max_wait` total. Used after wait_for_first_output to
    # let the TUI finish drawing before we write the prompt — solves
    # the race where bytes land in Claude Code's pre-readline buffer
    # and get discarded.
    #
    # Returns true only when output was observed AND has been quiet for
    # `grace` seconds. Returns false when `max_wait` elapses without
    # quieting OR when no output ever arrived (`@last_output_at` nil).
    # The previous "treat nil as already quiet" shortcut is what made
    # routed_prompt_delivered fire on dead PTYs — callers must see a
    # honest `false` so the prompt is not marked delivered.
    def wait_for_quiet(grace:, max_wait:)
      deadline = Time.current + max_wait
      loop do
        last = @last_output_at
        if last.nil?
          remaining = deadline - Time.current
          return false if remaining <= 0
          sleep [remaining, 0.05].min
          next
        end
        elapsed_quiet = Time.current - last
        return true if elapsed_quiet >= grace
        remaining = deadline - Time.current
        return false if remaining <= 0
        sleep [grace - elapsed_quiet, remaining, 0.05].min
      end
    end

    def initial_prompt_delivered?
      @initial_prompt_delivered
    end

    def mark_initial_prompt_delivered!
      @initial_prompt_delivered = true
    end

    # Records that an auto-wake nudge was just delivered to this live
    # session (or that a fresh spawn carried the wake prompt). Read by
    # SessionControl to coalesce near-simultaneous auto-wakes — see
    # recently_wake_nudged?.
    def mark_wake_nudged!(at: Time.current)
      @wake_nudge_mutex.synchronize { @last_wake_nudge_at = at }
    end

    # True when an auto-wake nudge was delivered within `within` seconds.
    # SessionControl uses this (only when called with coalesce_wake) to
    # skip a redundant submit_sequence write to a session that was just
    # told to read its inbox.
    def recently_wake_nudged?(within:)
      @wake_nudge_mutex.synchronize do
        last = @last_wake_nudge_at
        next false if last.nil?

        (Time.current - last) <= within
      end
    end

    # True when this Session was reattached from a TentacleSession record
    # whose metadata predates the always-write of `repo_root_fingerprint`.
    # SessionControl uses this to log + allow reuse instead of rejecting
    # the session as unverifiable on the first reattach after deploy.
    def pre_persistence_fingerprint?
      @pre_persistence_fingerprint
    end

    # True when stop() escalated to SIGKILL because the child ignored
    # SIGTERM within the grace window (or grace was 0). Set in both
    # PTY mode (line that flips @force_killed after Process.kill("KILL"))
    # and dtach mode (when DtachWrapper#stop returns :forced). Read by
    # SessionControl.terminate to surface escalated_to_kill in the API
    # response.
    def force_killed?
      @force_killed == true
    end

    def transcript
      @transcript_mutex.synchronize do
        next @transcript.dup if @transcript_dropped_bytes.zero?

        marker = "[live-truncated — dropped #{@transcript_dropped_bytes} leading bytes]\n"
        marker + @transcript
      end
    end

    # Returns true on a successful write, false when the channel is
    # dead (EIO/IOError swallowed) or no writer is available. Callers
    # that need delivery confirmation — SessionControl's reuse-path
    # routed_prompt write, in particular — must check the return value;
    # silently dropping a write would let a stale-session race report
    # the prompt as delivered when it never reached the agent.
    def write(data)
      return false unless @writer && alive?
      @writer.write(data)
      @writer.flush
      true
    rescue Errno::EIO, IOError
      false
    end

    # Bytes that act as "submit current input" for the spawned command's
    # TUI. Claude Code enables the Kitty keyboard protocol on startup, so
    # plain `\r`/`\n` written to its PTY land as literal newline text in
    # the input field — only the CSI `13 u` sequence is decoded as Enter.
    # Other commands (bash, etc.) keep the legacy `\r` behaviour.
    # Empirically validated 2026-04-27: writing `\r` to claude's master
    # left the prompt visible but unsubmitted; injecting `\e[13u` flushed
    # the input and triggered the agent loop.
    KITTY_ENTER = "\e[13u"

    def submit_sequence
      Array(@command).first.to_s == "claude" ? KITTY_ENTER : "\r"
    end

    def resize(cols:, rows:)
      return unless @writer
      winsize = [rows.to_i, cols.to_i, 0, 0].pack("SSSS")
      @writer.ioctl(0x5414, winsize)
    rescue Errno::EIO, IOError, Errno::ENOTTY
      nil
    end

    # `grace` is the maximum seconds to wait for the child to exit after
    # SIGTERM before escalating to SIGKILL. Default stays fast (0.5s) to
    # preserve existing call-site behaviour; shutdown hooks pass a longer
    # value so the child can flush output and run its own exit handlers.
    #
    # `detach_only: true` (dtach mode only) closes the local attach proxy
    # without killing the detached child. Used by Puma shutdown hooks so
    # a deploy does not terminate live tentacle sessions — the child
    # keeps running under its dtach session until bootstrap_sessions!
    # reattaches on the next boot. In PTY mode this flag is a no-op
    # safeguard (there is no decoupled child), so we fall through to the
    # regular kill path for backward compatibility.
    def stop(grace: 0.5, detach_only: false)
      if detach_only && dtach_mode?
        detach_without_killing
        return
      end

      exit_status = nil
      if dtach_mode?
        exit_status = stop_dtach_child(grace: grace)
      elsif @pid && process_alive?
        begin
          Process.kill("TERM", @pid)
          status = reap(timeout: grace)
          if status.nil?
            begin
              Process.kill("KILL", @pid)
              @force_killed = true
            rescue Errno::ESRCH, Errno::ECHILD
            end
            status = reap(timeout: 2)
          end
          exit_status = status&.exitstatus
        rescue Errno::ESRCH, Errno::ECHILD
        end
      end

      if @stop_unconfirmed
        # SIGKILL did not confirm death. Leave the record as `unknown` so
        # SupervisorJob / next bootstrap can retry — do NOT fire on_exit
        # (which would mark the session ended and persist a transcript
        # while the child is still running). Suppress any late on_exit
        # from the reader thread's ensure block for the same reason.
        Rails.logger.error(
          "[tentacle_runtime] dtach child for #{@tentacle_id} survived SIGKILL; " \
          "leaving record as 'unknown' for supervisor retry"
        )
        @suppress_on_exit = true
        reader_join_timeout = [grace, 0.3].min
        @reader_thread&.join(reader_join_timeout)
        @reader_thread&.kill if @reader_thread&.alive?
        @heartbeat_thread&.kill if @heartbeat_thread&.alive?
        close_streams
        mark_session_record_unknown
        return
      end

      reader_join_timeout = [grace, 0.3].min
      @reader_thread&.join(reader_join_timeout)
      @reader_thread&.kill if @reader_thread&.alive?
      @heartbeat_thread&.kill if @heartbeat_thread&.alive?
      close_streams
      fire_on_exit(exit_status: exit_status)
    end

    # Disconnect from the dtach session without killing the child.
    # The child keeps running under its dtach process; our local attach
    # proxy dies when we close its streams, and the next boot's
    # bootstrap_sessions! reattaches. Intentionally does NOT fire
    # on_exit — the session is still alive.
    def detach_without_killing
      close_streams
      @reader_thread&.kill if @reader_thread&.alive?
      @heartbeat_thread&.kill if @heartbeat_thread&.alive?
      # reap the local attach proxy so no zombie is left behind
      reap_attach(timeout: 1.0)
      @session_record&.touch_seen!
    end

    # Kill the detached child via DtachWrapper, then reap our local
    # attach proxy so no zombie is left behind. Returns the child's
    # exit_status when dtach propagated it through the attach, else nil.
    # Sets @stop_unconfirmed when the wrapper could not confirm death
    # (returned :still_alive) so Session#stop can skip fire_on_exit and
    # leave the record in `unknown` for supervisor retry.
    def stop_dtach_child(grace:)
      result = @dtach.stop(grace: grace)
      @force_killed = true if result == :forced
      @stop_unconfirmed = (result == :still_alive)

      status = reap_attach(timeout: [grace, 1.0].max)
      status&.exitstatus
    end

    def alive?
      return @dtach.alive? if dtach_mode?
      @pid ? process_alive? : false
    end

    # Strict liveness probe for the activate reuse path. The shallow
    # `alive?` check (Process.kill 0 only) returns true for zombies and
    # for PIDs that were reused by an unrelated process — both real
    # post-`systemctl restart` failure modes that left agents wedged
    # against dead PTYs and triggered a 4×-retry storm in 2026-04-29.
    #
    # On top of `alive?` this verifies the channel itself is usable:
    #   - in dtach mode: the runtime socket file must still exist (an
    #     abrupt SIGKILL of the dtach process leaves the FD slot empty
    #     even if the child PID was reused, so socket_exists? false is
    #     the unambiguous "respawn me" signal)
    #   - in either mode: the local writer must be open and accept a
    #     non-blocking probe (NUL byte in PTY mode — ignored by claude
    #     and bash TUIs; closed?-only check in dtach mode since the
    #     local writer is the attach proxy's PTY, not the child's)
    #
    # Returns false on any signal that the channel is dead, true only
    # when every layer says healthy. Callers that get false MUST
    # invalidate this Session entry instead of trying to write into it.
    def alive_for_reuse?
      return false unless alive?

      writer = @writer
      return false if writer.nil? || writer.closed?

      if dtach_mode?
        return false unless @dtach&.socket_exists?
      else
        writer.write_nonblock("\x00")
      end
      true
    rescue Errno::EPIPE, Errno::EIO, IOError, Errno::EBADF
      false
    rescue IO::WaitWritable
      # Buffer pressure but channel still open — alive.
      true
    end

    private

    def process_alive?
      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def spawn_process
      if ::TentacleRuntime.dtach_enabled?
        spawn_via_dtach
      else
        spawn_via_pty
      end
    end

    def spawn_via_pty
      args = [@env, *@command]
      spawn_opts = {}
      spawn_opts[:chdir] = @cwd.to_s if @cwd
      args << spawn_opts unless spawn_opts.empty?
      @reader, @writer, @pid = PTY.spawn(*args)

      # Persist a cross-process trace of this PTY session. The per-note
      # alive partial unique index makes a concurrent duplicate spawn
      # from another web process fail atomically — the loser kills its
      # just-spawned child and raises ForeignOwnedSession instead of
      # running a second runtime against the same inbox/worktree.
      begin
        @session_record = persist_pty_session_record!
      rescue ActiveRecord::RecordNotUnique
        cleanup_orphan_pty_child
        raise ForeignOwnedSession,
          "tentacle #{@tentacle_id} already has a live session owned by another web process"
      rescue StandardError
        # Post-spawn persistence failed for some other reason — do not
        # leave the child untracked; kill it and surface the failure.
        cleanup_orphan_pty_child
        raise
      end
    end

    def persist_pty_session_record!
      metadata = {}
      metadata["persistence"] = @persistence_descriptor if @persistence_descriptor
      metadata["repo_root_fingerprint"] = @repo_root_fingerprint
      TentacleSession.create!(
        tentacle_note_id: @tentacle_id,
        pid: @pid,
        host: Socket.gethostname,
        dtach_socket: nil,
        command: Array(@command).join(" "),
        cwd: @cwd&.to_s,
        started_at: @started_at,
        status: "alive",
        metadata: metadata,
        lease_token: SecureRandom.uuid,
        lease_expires_at: Time.current + LEASE_DURATION
      )
    end

    # Kills and reaps the PTY child spawned moments ago and closes its
    # streams — used when post-spawn persistence loses the cross-process
    # race, so no orphaned child or fd is left behind.
    def cleanup_orphan_pty_child
      Process.kill("KILL", @pid) if @pid
    rescue Errno::ESRCH, Errno::ECHILD
      # already gone
    ensure
      begin
        Process.waitpid(@pid, Process::WNOHANG) if @pid
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
      close_streams
      @pid = nil
    end

    # dtach mode: the command runs under `dtach -n` in its own detached
    # session. We spawn a local `dtach -a` proxy through PTY.spawn so the
    # reader/writer streams (and resize ioctl) work exactly like the
    # legacy path — only the lifecycle of the real child is decoupled
    # from this Puma process.
    def spawn_via_dtach
      runtime_dir = ENV.fetch("NEURAMD_TENTACLE_RUNTIME_DIR", Tentacles::DtachWrapper::DEFAULT_RUNTIME_DIR)
      @dtach = Tentacles::DtachWrapper.new(session_id: @tentacle_id, runtime_dir: runtime_dir)

      if @dtach.alive?
        # Adoption only when a vouching DB record matches the requested
        # identity. Attaching to an unowned socket would let later
        # stop/drain paths signal whatever pid the stale pidfile holds —
        # potentially an unrelated process. Verified identity: an alive
        # TentacleSession record for this note with the same dtach_socket
        # and the same command string as what the caller is requesting.
        @session_record = authorize_adoption!
      else
        @dtach.spawn(@command, cwd: @cwd, env: @env)
        begin
          @session_record = persist_tentacle_session_record!
        rescue StandardError
          # Post-spawn persistence failed. Do not leave a detached child
          # untracked — kill it, clean up the socket/pidfile, and raise so
          # the caller sees the failure instead of receiving a half-spawned
          # session masquerading as healthy.
          cleanup_orphan_after_persist_failure
          raise
        end
      end

      # Attach via PTY so the TTY winsize ioctl propagates through dtach
      # to the underlying child. The attach proxy is a short-lived process
      # local to Puma — killing it detaches the session without killing
      # the child.
      attach_cmd = ["dtach", "-a", @dtach.socket_path, "-E", "-z"]
      @reader, @writer, @attach_pid = PTY.spawn(*attach_cmd)
      @pid = @dtach.pid
    end

    def authorize_adoption!
      record = TentacleSession.alive.find_by(tentacle_note_id: @tentacle_id)
      unless record
        raise OrphanSocketError,
          "refusing to adopt orphan dtach socket #{@dtach.socket_path} for tentacle " \
          "#{@tentacle_id}: no TentacleSession record vouches for this process"
      end

      if record.dtach_socket != @dtach.socket_path
        raise OwnershipMismatchError,
          "TentacleSession record socket mismatch for #{@tentacle_id}: " \
          "record=#{record.dtach_socket.inspect} wrapper=#{@dtach.socket_path.inspect}"
      end

      expected_command = Array(@command).join(" ")
      if record.command.to_s != expected_command
        raise OwnershipMismatchError,
          "TentacleSession record command mismatch for #{@tentacle_id}: " \
          "record=#{record.command.inspect} requested=#{expected_command.inspect}"
      end

      record
    end

    def persist_tentacle_session_record!
      metadata = {}
      metadata["persistence"] = @persistence_descriptor if @persistence_descriptor
      # Persisted alongside `persistence` so reattach after a Puma
      # restart / autodeploy can rebuild the in-memory @repo_root_fingerprint
      # — without it, SessionControl#assert_session_fresh! sees nil and
      # silently skips the cross-repo guard. The key is ALWAYS written
      # (even when the value is nil) so reattach can distinguish
      # post-fix sessions from genuinely-legacy ones whose record predates
      # this persistence and which must be allowed to reuse without a
      # fingerprint to compare against.
      metadata["repo_root_fingerprint"] = @repo_root_fingerprint
      TentacleSession.create!(
        tentacle_note_id: @tentacle_id,
        pid: @dtach.pid,
        host: Socket.gethostname,
        dtach_socket: @dtach.socket_path,
        pid_file: @dtach.pid_path,
        command: Array(@command).join(" "),
        cwd: @cwd&.to_s,
        started_at: @started_at,
        status: "alive",
        metadata: metadata,
        lease_token: SecureRandom.uuid,
        lease_expires_at: Time.current + LEASE_DURATION
      )
    end

    def cleanup_orphan_after_persist_failure
      begin
        @dtach.stop(grace: 1.0)
      rescue StandardError => stop_err
        Rails.logger.error(
          "[tentacle_runtime] failed to stop orphan dtach child after persist failure: " \
          "#{stop_err.class}: #{stop_err.message}"
        )
      end
      begin
        @dtach.cleanup
      rescue StandardError
        # socket/pidfile removal is best-effort; supervisor sweep is the backstop
      end
    end

    def start_reader
      tentacle_id = @tentacle_id
      reader = @reader
      session = self
      @reader_thread = Thread.new do
        Rails.application.executor.wrap do
          begin
            loop do
              chunk = reader.readpartial(4096)
              chunk.force_encoding(Encoding::UTF_8)
              chunk.scrub!("?")
              session.append_to_transcript(chunk)
              session.signal_boot!
              TentacleChannel.broadcast_output(tentacle_id: tentacle_id, data: chunk)
            end
          rescue Errno::EIO, EOFError, IOError
            # Child closed PTY — process exited.
          ensure
            status = session.reap_for_exit(timeout: 0.2)
            TentacleChannel.broadcast_exit(
              tentacle_id: tentacle_id,
              status: status&.exitstatus
            )
            session.fire_on_exit(exit_status: status&.exitstatus)
            SESSIONS.delete(tentacle_id)
          end
        end
      end
    end

    # Single iteration of the lease renewal: CAS-update the row's
    # lease_expires_at while the lease_token still matches. Returns
    # :renewed on success, :fenced when the lease was reclaimed (a
    # foreign reaper rotated the token), :no_record when this session
    # has no persisted row. On :fenced this session self-fences —
    # the OS process is killed in a detached thread so it cannot
    # continue processing the same inbox/worktree as the replacement
    # spawn on the reclaiming host (Codex finding: OS-level split-brain
    # after lease reclamation).
    def renew_lease!
      return :no_record unless @session_record

      rows = TentacleSession.where(id: @session_record.id, lease_token: @session_record.lease_token)
        .update_all(
          lease_expires_at: Time.current + ::TentacleRuntime::LEASE_DURATION,
          last_seen_at: Time.current,
          updated_at: Time.current
        )
      return :renewed if rows.positive?

      Rails.logger.warn(
        "[tentacle_runtime] lease lost for #{@tentacle_id}: row was reaped by a foreign " \
        "reclaimer; self-fencing the local session to avoid OS-level split-brain"
      )
      # Dispatch stop in a fresh thread so the heartbeat thread (which
      # is the typical caller) does not deadlock when stop kills it.
      tentacle_id = @tentacle_id
      Thread.new { ::TentacleRuntime.stop(tentacle_id: tentacle_id) }
      :fenced
    end

    # Periodic heartbeat that renews the fencing lease on this session's
    # TentacleSession row via renew_lease!. The thread exits when the
    # session has fired on_exit (graceful), when the lease is reclaimed
    # by a foreign host (renew_lease! returns :fenced and self-fences),
    # or when there is no record to renew.
    def start_heartbeat
      return unless @session_record

      tentacle_id = @tentacle_id
      @heartbeat_thread = Thread.new do
        loop do
          sleep ::TentacleRuntime::HEARTBEAT_INTERVAL
          break if @on_exit_fired
          begin
            outcome = Rails.application.executor.wrap { renew_lease! }
            break if outcome == :fenced || outcome == :no_record
          rescue StandardError => e
            Rails.logger.warn(
              "[tentacle_runtime] heartbeat renewal failed for #{tentacle_id}: " \
              "#{e.class}: #{e.message}"
            )
          end
        end
      end
    end

    public

    def signal_boot!
      @boot_mutex.synchronize do
        next if @booted
        @booted = true
        @boot_cv.broadcast
      end
    end

    def append_to_transcript(chunk)
      total_bytes = @transcript_mutex.synchronize do
        @transcript << chunk
        if @transcript.bytesize > LIVE_TRANSCRIPT_CAP
          overflow = @transcript.bytesize - LIVE_TRANSCRIPT_CAP
          tail = @transcript.byteslice(overflow, LIVE_TRANSCRIPT_CAP)
          tail.force_encoding(Encoding::UTF_8).scrub!
          @transcript_dropped_bytes += overflow
          @transcript = +tail
        end
        @transcript.bytesize + @transcript_dropped_bytes
      end
      @last_output_at = Time.current
      check_context_warning!(total_bytes)
    end

    def check_context_warning!(total_bytes)
      return if @context_warning_fired
      return if @context_window_tokens <= 0

      estimated_tokens = total_bytes / TOKEN_BYTES_RATIO
      ratio = estimated_tokens.to_f / @context_window_tokens
      return if ratio < @context_warning_ratio

      should_fire = @context_warning_mutex.synchronize do
        next false if @context_warning_fired
        @context_warning_fired = true
        true
      end
      return unless should_fire

      fire_context_warning(ratio: ratio, estimated_tokens: estimated_tokens)
    end

    def fire_context_warning(ratio:, estimated_tokens:)
      TentacleChannel.broadcast_context_warning(
        tentacle_id: @tentacle_id,
        ratio: ratio,
        estimated_tokens: estimated_tokens
      )
    rescue StandardError => e
      Rails.logger.error("TentacleRuntime#context_warning failed: #{e.class}: #{e.message}")
    end

    def fire_on_exit(exit_status:)
      return if @suppress_on_exit

      should_fire = @on_exit_mutex.synchronize do
        next false if @on_exit_fired
        @on_exit_fired = true
        true
      end
      return unless should_fire

      # Stop the heartbeat eagerly: the loop checks @on_exit_fired
      # between sleeps, but we don't want to wait up to HEARTBEAT_INTERVAL.
      @heartbeat_thread&.kill if @heartbeat_thread&.alive?

      emit_exit_metric(exit_status)
      mark_session_record_ended(exit_status)

      return unless @on_exit
      @on_exit.call(
        transcript: transcript,
        command: @command,
        started_at: @started_at,
        ended_at: Time.current,
        exit_status: exit_status
      )
    rescue StandardError => e
      Rails.logger.error("TentacleRuntime#on_exit failed: #{e.class}: #{e.message}")
    end

    def mark_session_record_ended(exit_status)
      # Both backends persist a TentacleSession record now — dtach via
      # persist_tentacle_session_record!, PTY via persist_pty_session_record!.
      # The record must be finalized on exit either way, or the per-note
      # alive uniqueness index would block the next spawn forever.
      record = @session_record || TentacleSession.alive.find_by(tentacle_note_id: @tentacle_id)
      return unless record

      reason = exit_reason_for(exit_status)
      record.mark_ended!(reason: reason, exit_code: exit_status)
    rescue StandardError => e
      Rails.logger.error("[tentacle_runtime] failed to mark TentacleSession ended: #{e.class}: #{e.message}")
    end

    def mark_session_record_unknown
      return unless dtach_mode?
      record = @session_record || TentacleSession.alive.find_by(tentacle_note_id: @tentacle_id)
      return unless record
      record.mark_unknown!
    rescue StandardError => e
      Rails.logger.error("[tentacle_runtime] failed to mark TentacleSession unknown: #{e.class}: #{e.message}")
    end

    def exit_reason_for(exit_status)
      return "forced" if @force_killed
      return "unknown" if exit_status.nil?
      return "graceful" if exit_status.zero?
      "crash"
    end

    def emit_exit_metric(exit_status)
      reason =
        if @force_killed
          "forced"
        elsif exit_status.nil?
          "unknown"
        elsif exit_status.zero?
          "graceful"
        else
          "crash"
        end
      Neuramd::Metrics.emit(
        "tentacle_exit",
        {tentacle_id: @tentacle_id.to_s, reason: reason, exit_status: exit_status}
      )
    end

    # In dtach mode only the local attach proxy is our direct child; the
    # detached session's pid is reaped by PID 1. Exposed so start_reader
    # can ask for the right thing without knowing the mode.
    def reap_for_exit(timeout: 0.2)
      dtach_mode? ? reap_attach(timeout: timeout) : reap(timeout: timeout)
    end

    private

    def reap(timeout: 0.5)
      wait_and_reap(@pid, timeout: timeout)
    end

    def reap_attach(timeout: 0.5)
      wait_and_reap(@attach_pid, timeout: timeout)
    end

    def wait_and_reap(pid_to_wait, timeout:)
      return nil unless pid_to_wait
      deadline = Time.current + timeout
      loop do
        pid, status = Process.waitpid2(pid_to_wait, Process::WNOHANG)
        return status if pid
        break if Time.current > deadline
        sleep(0.02)
      end
      nil
    rescue Errno::ECHILD
      nil
    end

    def close_streams
      @reader&.close
      @writer&.close
    rescue IOError
      nil
    end
  end
end
