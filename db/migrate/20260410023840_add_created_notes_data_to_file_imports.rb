class AddCreatedNotesDataToFileImports < ActiveRecord::Migration[8.1]
  def change
    add_column :file_imports, :created_notes_data, :jsonb, default: []
  end
end
