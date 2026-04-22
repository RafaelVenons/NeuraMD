require "pty"
require "concurrent/map"

class TentacleRuntime
  SESSIONS = Concurrent::Map.new
  INITIAL_PROMPT_BOOT_DELAY = 1.5

  class << self
    def start(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil, initial_prompt: nil,
              context_warning_ratio: nil, context_window_tokens: nil)
      existing = SESSIONS[tentacle_id]
      return existing if existing&.alive?

      FileUtils.mkdir_p(cwd) if cwd
      session = Session.new(
        tentacle_id: tentacle_id,
        command: Array(command),
        cwd: cwd,
        env: env,
        on_exit: on_exit,
        context_warning_ratio: context_warning_ratio,
        context_window_tokens: context_window_tokens
      )
      SESSIONS[tentacle_id] = session
      schedule_initial_prompt(session, initial_prompt) if initial_prompt.present?
      session
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

    def reset!
      SESSIONS.each_value(&:stop)
      SESSIONS.clear
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

    attr_reader :tentacle_id, :pid, :started_at

    def initialize(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil,
                   context_warning_ratio: nil, context_window_tokens: nil)
      @tentacle_id = tentacle_id
      @command = command
      @cwd = cwd
      @env = self.class.default_env.merge(env).merge("NEURAMD_TENTACLE_ID" => tentacle_id.to_s)
      @on_exit = on_exit
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
      @started_at = Time.current
      spawn_process
      start_reader
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
    def stop(grace: 0.5)
      exit_status = nil
      if @pid && process_alive?
        begin
          Process.kill("TERM", @pid)
          status = reap(timeout: grace)
          if status.nil?
            begin
              Process.kill("KILL", @pid)
            rescue Errno::ESRCH, Errno::ECHILD
            end
            status = reap(timeout: 2)
          end
          exit_status = status&.exitstatus
        rescue Errno::ESRCH, Errno::ECHILD
        end
      end
      reader_join_timeout = [grace, 0.3].min
      @reader_thread&.join(reader_join_timeout)
      @reader_thread&.kill if @reader_thread&.alive?
      close_streams
      fire_on_exit(exit_status: exit_status)
    end

    def alive?
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
      args = [@env, *@command]
      spawn_opts = {}
      spawn_opts[:chdir] = @cwd.to_s if @cwd
      args << spawn_opts unless spawn_opts.empty?
      @reader, @writer, @pid = PTY.spawn(*args)
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
            status = reap(timeout: 0.2)
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
      return unless @on_exit
      should_fire = @on_exit_mutex.synchronize do
        next false if @on_exit_fired
        @on_exit_fired = true
        true
      end
      return unless should_fire
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

    private

    def reap(timeout: 0.5)
      return nil unless @pid
      deadline = Time.current + timeout
      loop do
        pid, status = Process.waitpid2(@pid, Process::WNOHANG)
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
