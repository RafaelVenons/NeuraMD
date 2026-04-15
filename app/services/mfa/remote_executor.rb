require "open3"
require "timeout"
require_relative "error"

module Mfa
  class RemoteExecutor
    SSH_HOST = ENV.fetch("MFA_SSH_HOST", "venom@bazzite.local")
    SSH_TIMEOUT = ENV.fetch("MFA_SSH_TIMEOUT", "10").to_i
    EXEC_TIMEOUT = ENV.fetch("MFA_EXEC_TIMEOUT", "300").to_i # 5 min max

    # MFA now runs inside a podman container on bazzite. Commands are wrapped
    # with `podman exec` so callers keep passing plain `mfa ...` strings.
    MFA_CONTAINER = ENV.fetch("MFA_CONTAINER", "mfa-service")

    def self.call(command)
      new.execute(command)
    end

    # Copy a local directory to the bazzite host under the shared mfa-data tree.
    # The container sees the same contents at $MFA_REMOTE_ROOT (default /data).
    def push_dir(local_dir, remote_dir)
      rsync(local_dir.to_s.chomp("/") + "/", "#{SSH_HOST}:#{remote_dir}/", ensure_remote: remote_dir)
    end

    # Pull a directory back from bazzite to the local filesystem.
    def pull_dir(remote_dir, local_dir)
      FileUtils.mkdir_p(local_dir)
      rsync("#{SSH_HOST}:#{remote_dir}/", local_dir.to_s.chomp("/") + "/")
    end

    # Remove one or more directories on the bazzite host (best effort).
    def execute_host_cleanup(*remote_dirs)
      quoted = remote_dirs.map { |d| shell_quote(d) }.join(" ")
      execute_host("rm -rf #{quoted}")
    end

    def execute(command)
      wrapped = "podman exec #{MFA_CONTAINER} sh -c #{shell_quote(command)}"
      ssh_cmd = [
        "ssh",
        "-o", "ConnectTimeout=#{SSH_TIMEOUT}",
        "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=yes",
        SSH_HOST,
        wrapped
      ]

      stdout, stderr, status = nil
      Timeout.timeout(EXEC_TIMEOUT, TransientError, "MFA command timed out after #{EXEC_TIMEOUT}s") do
        stdout, stderr, status = Open3.capture3(*ssh_cmd)
      end

      unless status.success?
        raise ExecutionError, "SSH command failed (exit #{status.exitstatus}): #{stderr.strip}"
      end

      stdout
    end

    private

    def rsync(src, dest, ensure_remote: nil)
      if ensure_remote
        execute_host("mkdir -p #{shell_quote(ensure_remote)}")
      end
      cmd = [
        "rsync", "-az", "--delete",
        "-e", "ssh -o ConnectTimeout=#{SSH_TIMEOUT} -o StrictHostKeyChecking=no -o BatchMode=yes",
        src, dest
      ]
      _stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        raise ExecutionError, "rsync failed (exit #{status.exitstatus}): #{stderr.strip}"
      end
    end

    # Run a plain shell command on the bazzite host (not inside the container).
    def execute_host(command)
      ssh_cmd = [
        "ssh",
        "-o", "ConnectTimeout=#{SSH_TIMEOUT}",
        "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=yes",
        SSH_HOST,
        command
      ]
      _stdout, stderr, status = Open3.capture3(*ssh_cmd)
      unless status.success?
        raise ExecutionError, "host command failed (exit #{status.exitstatus}): #{stderr.strip}"
      end
    end

    def shell_quote(str)
      "'" + str.gsub("'", %q('\\''))+ "'"
    end
  end
end
