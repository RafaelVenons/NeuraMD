require "pty"
require "concurrent/map"

class TentacleRuntime
  SESSIONS = Concurrent::Map.new
  INITIAL_PROMPT_BOOT_DELAY = 1.5

  class << self
    def start(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil, initial_prompt: nil)
      existing = SESSIONS[tentacle_id]
      return existing if existing&.alive?

      FileUtils.mkdir_p(cwd) if cwd
      session = Session.new(
        tentacle_id: tentacle_id,
        command: Array(command),
        cwd: cwd,
        env: env,
        on_exit: on_exit
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

    def reset!
      SESSIONS.each_value(&:stop)
      SESSIONS.clear
    end
  end

  class Session
    DEFAULT_ENV = {
      "TERM" => "xterm-256color",
      "LANG" => ENV["LANG"] || "en_US.UTF-8"
    }.freeze
    LIVE_TRANSCRIPT_CAP = 200_000

    attr_reader :tentacle_id, :pid, :started_at

    def initialize(tentacle_id:, command:, cwd: nil, env: {}, on_exit: nil)
      @tentacle_id = tentacle_id
      @command = command
      @cwd = cwd
      @env = DEFAULT_ENV.merge(env)
      @on_exit = on_exit
      @transcript = +""
      @transcript_mutex = Mutex.new
      @transcript_dropped_bytes = 0
      @on_exit_fired = false
      @on_exit_mutex = Mutex.new
      @boot_mutex = Mutex.new
      @boot_cv = ConditionVariable.new
      @booted = false
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

    def stop
      exit_status = nil
      if @pid && process_alive?
        begin
          Process.kill("TERM", @pid)
          status = reap(timeout: 0.5)
          exit_status = status&.exitstatus
        rescue Errno::ESRCH, Errno::ECHILD
        end
      end
      @reader_thread&.join(0.3)
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
      @transcript_mutex.synchronize do
        @transcript << chunk
        next if @transcript.bytesize <= LIVE_TRANSCRIPT_CAP

        overflow = @transcript.bytesize - LIVE_TRANSCRIPT_CAP
        tail = @transcript.byteslice(overflow, LIVE_TRANSCRIPT_CAP)
        tail.force_encoding(Encoding::UTF_8).scrub!
        @transcript_dropped_bytes += overflow
        @transcript = +tail
      end
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
