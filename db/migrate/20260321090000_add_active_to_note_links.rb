class AddActiveToNoteLinks < ActiveRecord::Migration[8.1]
  def up
    add_column :note_links, :active, :boolean, default: true, null: false
    add_index :note_links, :active
  end

  def down
    remove_index :note_links, :active
    remove_column :note_links, :active
  end
end
