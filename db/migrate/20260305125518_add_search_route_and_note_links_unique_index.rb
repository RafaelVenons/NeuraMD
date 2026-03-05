class AddSearchRouteAndNoteLinksUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    # Enforce deduplication: one link per (src, dst, hier_role) combination.
    # hier_role is nullable so we use a partial index for each case.
    add_index :note_links, [:src_note_id, :dst_note_id],
              unique: true,
              where: "hier_role IS NULL",
              name: "index_note_links_unique_src_dst_no_role"

    add_index :note_links, [:src_note_id, :dst_note_id, :hier_role],
              unique: true,
              where: "hier_role IS NOT NULL",
              name: "index_note_links_unique_src_dst_role"
  end
end
