require "open3"
require "timeout"
require_relative "error"

module Mfa
  class RemoteExecutor
    SSH_HOST = ENV.fetch("MFA_SSH_HOST", "rafael@bazzite.local")
    SSH_TIMEOUT = ENV.fetch("MFA_SSH_TIMEOUT", "10").to_i
    EXEC_TIMEOUT = ENV.fetch("MFA_EXEC_TIMEOUT", "300").to_i # 5 min max
    def self.call(command)
      new.execute(command)
    end

    # MFA conda env bin dir — needed because SSH non-login shells don't activate conda
    MFA_ENV_BIN = ENV.fetch("MFA_ENV_BIN", "~/.local/share/mamba/envs/mfa/bin")

    def execute(command)
      wrapped = "export PATH=#{MFA_ENV_BIN}:$PATH && #{command}"
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
  end
end
