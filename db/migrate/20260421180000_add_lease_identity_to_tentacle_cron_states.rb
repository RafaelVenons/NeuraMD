class AddLeaseIdentityToTentacleCronStates < ActiveRecord::Migration[8.1]
  def change
    add_column :tentacle_cron_states, :lease_pid,  :integer, null: true
    add_column :tentacle_cron_states, :lease_host, :string,  null: true
  end
end
