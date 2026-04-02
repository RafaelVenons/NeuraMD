class CreateNoteAliases < ActiveRecord::Migration[8.0]
  def change
    create_table :note_aliases, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :note, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.timestamps
    end

    add_index :note_aliases, "lower(name)", unique: true, name: "index_note_aliases_on_lower_name"
    add_index :note_aliases, :name, opclass: :gin_trgm_ops, using: :gin, name: "index_note_aliases_on_name_trgm"
  end
end
