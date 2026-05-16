class AddLeaseColumnsToTentacleSessions < ActiveRecord::Migration[8.1]
  def change
    # Fencing lease for the tentacle-session row. The owner sets
    # lease_token at spawn and CAS-renews lease_expires_at on each
    # heartbeat; a cross-host reaper only reclaims when the lease has
    # genuinely expired (vs. a best-effort timestamp comparison that
    # could mis-fence a briefly stalled owner). Token rotation on reap
    # ensures a re-awakened stale owner's renewals don't bring the row
    # back to alive.
    add_column :tentacle_sessions, :lease_token, :string
    add_column :tentacle_sessions, :lease_expires_at, :datetime

    add_index :tentacle_sessions, :lease_expires_at,
      where: "status = 'alive'",
      name: "index_tentacle_sessions_on_lease_expiry_alive"
  end
end
