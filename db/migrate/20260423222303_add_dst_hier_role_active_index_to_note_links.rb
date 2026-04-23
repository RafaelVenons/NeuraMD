class AddDstHierRoleActiveIndexToNoteLinks < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_note_links_on_dst_hier_role_active"

  def up
    return if index_exists?(:note_links, [:dst_note_id, :hier_role], name: INDEX_NAME)

    add_index :note_links, [:dst_note_id, :hier_role],
      where: "active = TRUE",
      name: INDEX_NAME
  end

  def down
    remove_index :note_links, name: INDEX_NAME, if_exists: true
  end
end
