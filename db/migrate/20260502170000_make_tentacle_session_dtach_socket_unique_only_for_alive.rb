class MakeTentacleSessionDtachSocketUniqueOnlyForAlive < ActiveRecord::Migration[8.1]
  # Codex P1 from PR #55: invalidate_stale_session! marks the existing alive
  # record exited but leaves dtach_socket untouched. The fresh-spawn path
  # immediately below tries to insert a new record with the same socket path
  # (sockets are derived from the deterministic tentacle UUID), which violates
  # the existing global unique index — the one-cycle recovery the PR was
  # supposed to fix actually fails.
  #
  # The real invariant is per-status: only one ALIVE session may claim a given
  # socket. Exited records keep their socket value as forensic state without
  # blocking the next lifecycle. Postgres partial indexes encode this
  # directly.
  def change
    remove_index :tentacle_sessions, name: "index_tentacle_sessions_on_dtach_socket"
    add_index :tentacle_sessions, :dtach_socket,
      unique: true,
      where: "status = 'alive'",
      name: "index_tentacle_sessions_on_dtach_socket_alive"
  end
end
