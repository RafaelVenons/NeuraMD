class AddLeaseTokenToTentacleCronStates < ActiveRecord::Migration[8.1]
  def change
    add_column :tentacle_cron_states, :lease_token, :string, null: true
  end
end
