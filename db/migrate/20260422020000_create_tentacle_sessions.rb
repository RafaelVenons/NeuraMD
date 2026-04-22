class CreateTentacleSessions < ActiveRecord::Migration[8.1]
  def up
    create_table :tentacle_sessions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid     :tentacle_note_id,     null: false
      t.integer  :pid
      t.string   :dtach_socket,         null: false
      t.string   :pid_file
      t.string   :command,              null: false
      t.string   :cwd
      t.datetime :started_at,           null: false
      t.datetime :last_seen_at
      t.datetime :ended_at
      t.string   :status,               null: false, default: "alive"
      t.string   :exit_reason
      t.integer  :exit_code
      t.string   :transcript_tail_path
      t.jsonb    :metadata,             null: false, default: {}
      t.timestamps
    end

    add_foreign_key :tentacle_sessions, :notes,
      column: :tentacle_note_id, on_delete: :cascade
    add_index :tentacle_sessions, :tentacle_note_id
    add_index :tentacle_sessions, :status
    add_index :tentacle_sessions, :pid
    add_index :tentacle_sessions, :dtach_socket, unique: true
    add_index :tentacle_sessions, [:tentacle_note_id, :status]
  end

  def down
    drop_table :tentacle_sessions
  end
end
