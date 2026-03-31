class AddPropertiesDataToNoteRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :note_revisions, :properties_data, :jsonb, null: false, default: {}
    add_index  :note_revisions, :properties_data, using: :gin, name: "index_note_revisions_on_properties_data"
  end
end
