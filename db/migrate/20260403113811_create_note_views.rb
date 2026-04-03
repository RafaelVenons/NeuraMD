class CreateNoteViews < ActiveRecord::Migration[8.1]
  def change
    create_table :note_views, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :name,         null: false
      t.string  :filter_query, null: false, default: ""
      t.string  :display_type, null: false, default: "table"
      t.jsonb   :sort_config,  null: false, default: {}
      t.jsonb   :columns,      null: false, default: []
      t.integer :position,     null: false, default: 0
      t.timestamps
    end

    add_index :note_views, :position
  end
end
