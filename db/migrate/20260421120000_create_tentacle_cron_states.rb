class CreateTentacleCronStates < ActiveRecord::Migration[8.1]
  def up
    create_table :tentacle_cron_states, id: false do |t|
      t.uuid     :note_id,           null: false, primary_key: true
      t.datetime :last_fired_at,     null: true
      t.datetime :last_attempted_at, null: true
      t.timestamps
    end

    add_foreign_key :tentacle_cron_states, :notes, column: :note_id, on_delete: :cascade

    PropertyDefinition.find_or_create_by!(key: "cron_expr") do |d|
      d.value_type = "text"
      d.label = "Expressão cron"
      d.description = "Cron expression (minute hour day month weekday) parseada por Fugit::Cron. Ex: '0 9 * * MON'."
      d.system = true
    end
  end

  def down
    drop_table :tentacle_cron_states
    # PropertyDefinition cron_expr intencionalmente mantido — pode estar referenciado
    # em properties_data de revisões existentes.
  end
end
