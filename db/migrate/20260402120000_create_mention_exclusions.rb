class CreateMentionExclusions < ActiveRecord::Migration[8.0]
  def change
    create_table :mention_exclusions, id: :uuid do |t|
      t.references :note, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.references :source_note, type: :uuid, null: false, foreign_key: {to_table: :notes, on_delete: :cascade}
      t.string :matched_term, null: false
      t.timestamps
    end

    add_index :mention_exclusions, [:note_id, :source_note_id, :matched_term],
      unique: true, name: "idx_mention_exclusions_unique"
  end
end
