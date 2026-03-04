class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.string :note_kind, null: false, default: "markdown"
      t.string :detected_language
      # head_revision_id added after note_revisions table is created
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :notes, :slug, unique: true
    add_index :notes, :deleted_at
    add_index :notes, :title, using: :gin, opclass: :gin_trgm_ops
  end
end
