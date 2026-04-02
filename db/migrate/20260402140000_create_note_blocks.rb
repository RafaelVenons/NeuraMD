class CreateNoteBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :note_blocks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :note, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.string :block_id, null: false
      t.text :content, null: false
      t.string :block_type, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_index :note_blocks, [:note_id, :block_id], unique: true, name: "idx_note_blocks_note_block_id"
    add_index :note_blocks, [:note_id, :position], name: "idx_note_blocks_note_position"
    add_index :note_blocks, :content, opclass: :gin_trgm_ops, using: :gin, name: "idx_note_blocks_content_trgm"
  end
end
