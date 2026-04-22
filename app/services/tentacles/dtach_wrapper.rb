require "fileutils"
require "shellwords"

module Tentacles
  # Thin shell around the `dtach(1)` binary. Each instance represents
  # one detached PTY session identified by a Unix socket under
  # `runtime_dir`. The wrapper spawns the child through a `/bin/sh -c`
  # stub that writes its own pid to a companion file, so callers can
  # signal the real child later without relying on dtach exposing it.
  #
  # The wrapper is intentionally stateless between calls — it re-reads
  # the pidfile every time. Restart safety: after a Puma restart, a
  # freshly constructed DtachWrapper with the same session_id and
  # runtime_dir sees the same socket + pidfile on disk and operates on
  # the same child.
  class DtachWrapper
    DEFAULT_RUNTIME_DIR = "/run/nm-tentacles".freeze
    DEFAULT_SPAWN_TIMEOUT = 3.0
    DEFAULT_STOP_GRACE = 5.0
    SIGKILL_REAP_WAIT = 1.0

    class SpawnError < StandardError; end
    class DtachUnavailable < StandardError; end

    attr_reader :session_id, :socket_path, :pid_path, :runtime_dir

    def initialize(session_id:, runtime_dir: DEFAULT_RUNTIME_DIR)
      @session_id = session_id.to_s
      raise ArgumentError, "session_id cannot be blank" if @session_id.strip.empty?

      @runtime_dir = runtime_dir
      @socket_path = File.join(runtime_dir, "#{@session_id}.sock")
      @pid_path = File.join(runtime_dir, "#{@session_id}.pid")
    end

    # Spawns the command detached. Returns the child pid or raises
    # SpawnError. `dtach -n` itself exits after forking the detached
    # process, so we reap it and then poll for the pidfile.
    def spawn(command, cwd: nil, env: {}, timeout: DEFAULT_SPAWN_TIMEOUT)
      self.class.ensure_available!
      FileUtils.mkdir_p(@runtime_dir)
      FileUtils.rm_f(@pid_path)  # stale pid from a prior session would confuse await_pid_file

      cmd_tokens = Array(command)
      raise ArgumentError, "command cannot be empty" if cmd_tokens.empty?

      stub = build_stub(cmd_tokens)
      spawn_env = env.merge("NEURAMD_TENTACLE_SESSION_ID" => @session_id)
      spawn_opts = {close_others: true}
      spawn_opts[:chdir] = cwd.to_s if cwd

      dtach_pid = Process.spawn(
        spawn_env,
        "dtach", "-n", @socket_path, "-E", "-z", "/bin/sh", "-c", stub,
        spawn_opts
      )
      _, status = Process.waitpid2(dtach_pid)
      raise SpawnError, "dtach exited with status #{status.exitstatus}" unless status.success?

      await_pid_file(deadline: Time.now + timeout)
    end

    def pid
      raw = File.read(@pid_path).strip
      raw.empty? ? nil : Integer(raw)
    rescue Errno::ENOENT, ArgumentError
      nil
    end

    def alive?
      p = pid
      return false unless p
      Process.kill(0, p)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def socket_exists?
      File.socket?(@socket_path)
    end

    # SIGTERM the child, wait grace seconds, escalate to SIGKILL if
    # still alive. Returns :stopped | :forced | :already_gone.
    def stop(grace: DEFAULT_STOP_GRACE)
      current_pid = pid
      return :already_gone unless current_pid
      return :already_gone unless alive?

      begin
        Process.kill("TERM", current_pid)
      rescue Errno::ESRCH
        return :already_gone
      end

      wait_until_dead(grace)
      return :stopped unless alive?

      begin
        Process.kill("KILL", current_pid)
      rescue Errno::ESRCH
        return :stopped
      end
      wait_until_dead(SIGKILL_REAP_WAIT)
      :forced
    end

    def cleanup
      FileUtils.rm_f(@socket_path)
      FileUtils.rm_f(@pid_path)
    end

    # Single-process memoization: once we know dtach is on PATH we do
    # not pay for another `command -v` lookup per spawn.
    def self.ensure_available!
      return if @available
      raise DtachUnavailable, "dtach binary not found in PATH" unless dtach_on_path?
      @available = true
    end

    def self.reset_availability_cache!
      @available = nil
    end

    def self.dtach_on_path?
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, "dtach"))
      end
    end

    private

    def build_stub(tokens)
      escaped = tokens.map { |t| Shellwords.escape(t.to_s) }.join(" ")
      "printf '%d' \"$$\" > #{Shellwords.escape(@pid_path)}; exec #{escaped}"
    end

    def await_pid_file(deadline:)
      loop do
        p = pid
        return p if p
        raise SpawnError, "timed out waiting for pid file at #{@pid_path}" if Time.now > deadline
        sleep(0.02)
      end
    end

    def wait_until_dead(timeout)
      deadline = Time.now + timeout
      while alive? && Time.now < deadline
        sleep(0.05)
      end
    end
  end
end
