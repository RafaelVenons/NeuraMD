class AddPreviewFieldsToFileImports < ActiveRecord::Migration[8.1]
  def change
    add_column :file_imports, :suggested_splits, :jsonb, default: []
    add_column :file_imports, :confirmed_splits, :jsonb
  end
end
