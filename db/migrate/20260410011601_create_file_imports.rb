class CreateFileImports < ActiveRecord::Migration[8.1]
  def change
    create_table :file_imports, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string  :base_tag,          null: false
      t.string  :import_tag,        null: false
      t.string  :extra_tags
      t.integer :split_level
      t.string  :original_filename, null: false
      t.string  :status,            null: false, default: "pending"
      t.text    :error_message
      t.integer :notes_created,     default: 0
      t.text    :converted_markdown
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
