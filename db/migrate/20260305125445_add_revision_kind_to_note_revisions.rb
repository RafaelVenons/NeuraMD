class AddRevisionKindToNoteRevisions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TYPE note_revision_kind AS ENUM ('draft', 'checkpoint');
    SQL

    add_column :note_revisions, :revision_kind, :note_revision_kind, null: false, default: "checkpoint"

    # Existing revisions are all considered checkpoints
    execute "UPDATE note_revisions SET revision_kind = 'checkpoint'"

    add_index :note_revisions, [:note_id, :revision_kind],
              where: "revision_kind = 'draft'",
              name: "index_note_revisions_draft_per_note"
  end

  def down
    remove_index :note_revisions, name: "index_note_revisions_draft_per_note"
    remove_column :note_revisions, :revision_kind
    execute "DROP TYPE note_revision_kind"
  end
end
