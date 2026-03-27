require "open3"
require "timeout"
require_relative "error"

module Mfa
  class RemoteExecutor
    SSH_HOST = ENV.fetch("MFA_SSH_HOST", "rafael@AIrch.local")
    SSH_TIMEOUT = ENV.fetch("MFA_SSH_TIMEOUT", "10").to_i
    EXEC_TIMEOUT = ENV.fetch("MFA_EXEC_TIMEOUT", "300").to_i # 5 min max
    MFA_CONTAINER = ENV.fetch("MFA_CONTAINER", "mfa")

    def self.call(command)
      new.execute(command)
    end

    def execute(command)
      ssh_cmd = [
        "ssh",
        "-o", "ConnectTimeout=#{SSH_TIMEOUT}",
        "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=yes",
        SSH_HOST,
        command
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

    def docker_exec(mfa_command)
      execute("docker exec #{MFA_CONTAINER} #{mfa_command}")
    end
  end
end
