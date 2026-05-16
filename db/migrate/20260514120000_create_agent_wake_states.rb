class CreateAgentWakeStates < ActiveRecord::Migration[8.1]
  def up
    create_table :agent_wake_states, id: false do |t|
      t.uuid     :note_id,              null: false, primary_key: true
      t.datetime :last_wake_attempt_at, null: true
      t.timestamps
    end

    add_foreign_key :agent_wake_states, :notes, column: :note_id, on_delete: :cascade
  end

  def down
    drop_table :agent_wake_states
  end
end
