class CreateNoteHeadings < ActiveRecord::Migration[8.0]
  def change
    create_table :note_headings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :note, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.integer :level, null: false
      t.string :text, null: false
      t.string :slug, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_index :note_headings, [:note_id, :slug], unique: true, name: "idx_note_headings_note_slug"
    add_index :note_headings, [:note_id, :position], name: "idx_note_headings_note_position"
    add_index :note_headings, :text, opclass: :gin_trgm_ops, using: :gin, name: "idx_note_headings_text_trgm"
  end
end
