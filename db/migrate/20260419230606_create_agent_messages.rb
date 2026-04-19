class CreateAgentMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid     :from_note_id, null: false
      t.uuid     :to_note_id,   null: false
      t.text     :content,      null: false
      t.datetime :delivered_at
      t.timestamps
    end

    add_foreign_key :agent_messages, :notes, column: :from_note_id, on_delete: :cascade
    add_foreign_key :agent_messages, :notes, column: :to_note_id,   on_delete: :cascade

    add_index :agent_messages, [:to_note_id,   :delivered_at, :created_at], name: "idx_agent_messages_inbox"
    add_index :agent_messages, [:from_note_id, :created_at],                name: "idx_agent_messages_outbox"
  end
end
