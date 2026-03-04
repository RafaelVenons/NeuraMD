class CreateNoteRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :note_revisions, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :note, null: false, foreign_key: true, type: :uuid
      t.references :author, foreign_key: {to_table: :users}, type: :uuid
      t.uuid :base_revision_id  # FK added below (self-referential)
      t.text :content_markdown, null: false  # encrypted via AR Encryption
      t.text :content_plain                  # derived from markdown, for search
      t.string :change_summary
      t.boolean :ai_generated, null: false, default: false

      t.timestamps
    end

    add_foreign_key :note_revisions, :note_revisions,
      column: :base_revision_id, on_delete: :nullify

    add_index :note_revisions, :created_at
    # GIN index for full-text search on content_plain
    add_index :note_revisions, "to_tsvector('simple', coalesce(content_plain, ''))",
      name: "index_note_revisions_on_content_plain_tsvector",
      using: :gin
  end
end
