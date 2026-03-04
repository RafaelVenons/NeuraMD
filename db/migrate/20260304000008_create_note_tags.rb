class CreateNoteTags < ActiveRecord::Migration[8.1]
  def change
    create_table :note_tags, id: false do |t|
      t.references :note, null: false, foreign_key: true, type: :uuid
      t.references :tag, null: false, foreign_key: true, type: :uuid
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :note_tags, [:note_id, :tag_id], unique: true
  end
end
