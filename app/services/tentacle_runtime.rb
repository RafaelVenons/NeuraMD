require "pty"
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

  class << self
    # Whether the detached (dtach) backend is enabled. When false the
    # runtime keeps the legacy PTY.spawn path, so flipping this on/off
    # is a reversible switch with no migration.
    def dtach_enabled?
      ENV["NEURAMD_FEATURE_DTACH"].to_s.downcase == "on"
    end

    def start(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil, persistence: nil,
              initial_prompt: nil, context_warning_ratio: nil, context_window_tokens: nil,
              repo_root_fingerprint: nil)
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
          repo_root_fingerprint: repo_root_fingerprint
        )
        SESSIONS[tentacle_id] = session
        schedule_initial_prompt(session, initial_prompt) if initial_prompt.present?
        Neuramd::Metrics.emit("tentacle_spawn", {tentacle_id: tentacle_id.to_s, command: Array(command).first})
        session
      end
    end

    private

    def schedule_initial_prompt(session, prompt)
      Thread.new do
        Rails.application.executor.wrap do
          session.wait_for_first_output(timeout: INITIAL_PROMPT_BOOT_DELAY)
          session.write("#{prompt}\n")
        rescue StandardError => e
          Rails.logger.error("TentacleRuntime initial_prompt failed: #{e.class}: #{e.message}")
        end
      end
    end

    public

    def write(tentacle_id:, data:)
      SESSIONS[tentacle_id]&.write(data)
    end

    def resize(tentacle_id:, cols:, rows:)
      SESSIONS[tentacle_id]&.resize(cols: cols, rows: rows)
    end

    def stop(tentacle_id:)
      session = SESSIONS.delete(tentacle_id)
      session&.stop
    end

    def get(tentacle_id)
      SESSIONS[tentacle_id]
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
    # Rails boot. No-op unless dtach is enabled.
    def bootstrap_sessions!
      return 0 unless dtach_enabled?

      reattached = 0
      TentacleSession.alive.find_each do |record|
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

      descriptor = record.metadata.is_a?(Hash) ? record.metadata["persistence"] : nil
      reconstructed_on_exit =
        if descriptor
          Persistence.build_on_exit(descriptor, tentacle_id: record.tentacle_note_id)
        end

      session = Session.new(
        tentacle_id: record.tentacle_note_id,
        command: command,
        cwd: record.cwd,
        session_record: record,
        on_exit: reconstructed_on_exit
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

    attr_reader :tentacle_id, :pid, :started_at, :dtach, :cwd, :repo_root_fingerprint

    def initialize(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil,
                   context_warning_ratio: nil, context_window_tokens: nil,
                   session_record: nil, persistence_descriptor: nil,
                   repo_root_fingerprint: nil)
      @tentacle_id = tentacle_id
      @command = command
      @cwd = cwd
      @repo_root_fingerprint = repo_root_fingerprint
      @env = self.class.default_env.merge(env).merge("NEURAMD_TENTACLE_ID" => tentacle_id.to_s)
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
      @context_warning_ratio = (context_warning_ratio || DEFAULT_CONTEXT_WARNING_RATIO).to_f
      @context_window_tokens = (context_window_tokens || DEFAULT_CONTEXT_WINDOW_TOKENS).to_i
      @context_warning_fired = false
      @context_warning_mutex = Mutex.new
      @started_at = session_record&.started_at || Time.current
      @dtach = nil
      @attach_pid = nil
      @session_record = session_record
      spawn_process
      start_reader
    end

    def dtach_mode?
      !@dtach.nil?
    end

    def wait_for_first_output(timeout:)
      @boot_mutex.synchronize do
        next if @booted
        @boot_cv.wait(@boot_mutex, timeout)
      end
    end

    def transcript
      @transcript_mutex.synchronize do
        next @transcript.dup if @transcript_dropped_bytes.zero?

        marker = "[live-truncated — dropped #{@transcript_dropped_bytes} leading bytes]\n"
        marker + @transcript
      end
    end

    def write(data)
      return unless @writer && alive?
      @writer.write(data)
      @writer.flush
    rescue Errno::EIO, IOError
      nil
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
        close_streams
        mark_session_record_unknown
        return
      end

      reader_join_timeout = [grace, 0.3].min
      @reader_thread&.join(reader_join_timeout)
      @reader_thread&.kill if @reader_thread&.alive?
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
      metadata = @persistence_descriptor ? {"persistence" => @persistence_descriptor} : {}
      TentacleSession.create!(
        tentacle_note_id: @tentacle_id,
        pid: @dtach.pid,
        dtach_socket: @dtach.socket_path,
        pid_file: @dtach.pid_path,
        command: Array(@command).join(" "),
        cwd: @cwd&.to_s,
        started_at: @started_at,
        status: "alive",
        metadata: metadata
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
      return unless dtach_mode?
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
