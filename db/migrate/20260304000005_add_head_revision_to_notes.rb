class AddHeadRevisionToNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :head_revision_id, :uuid
    add_foreign_key :notes, :note_revisions,
      column: :head_revision_id, on_delete: :nullify
    add_index :notes, :head_revision_id
  end
end
