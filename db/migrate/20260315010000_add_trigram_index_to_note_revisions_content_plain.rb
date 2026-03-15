class AddTrigramIndexToNoteRevisionsContentPlain < ActiveRecord::Migration[8.1]
  def change
    add_index :note_revisions, :content_plain, using: :gin, opclass: :gin_trgm_ops
  end
end
