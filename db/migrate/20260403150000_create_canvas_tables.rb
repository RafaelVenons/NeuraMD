class CreateCanvasTables < ActiveRecord::Migration[8.1]
  def change
    create_table :canvas_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :name,     null: false
      t.jsonb   :viewport, null: false, default: {"x" => 0, "y" => 0, "zoom" => 1.0}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :canvas_documents, :position

    create_table :canvas_nodes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :canvas_document, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.string  :node_type, null: false, default: "note"
      t.uuid    :note_id
      t.float   :x,         null: false, default: 0.0
      t.float   :y,         null: false, default: 0.0
      t.float   :width,     null: false, default: 240.0
      t.float   :height,    null: false, default: 120.0
      t.jsonb   :data,      null: false, default: {}
      t.integer :z_index,   null: false, default: 0
      t.timestamps
    end
    add_index :canvas_nodes, :note_id
    add_foreign_key :canvas_nodes, :notes, column: :note_id, on_delete: :nullify

    create_table :canvas_edges, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :canvas_document, type: :uuid, null: false, foreign_key: {on_delete: :cascade}
      t.references :source_node, type: :uuid, null: false, foreign_key: {to_table: :canvas_nodes, on_delete: :cascade}
      t.references :target_node, type: :uuid, null: false, foreign_key: {to_table: :canvas_nodes, on_delete: :cascade}
      t.string  :edge_type, null: false, default: "arrow"
      t.string  :label
      t.jsonb   :style,     null: false, default: {}
      t.timestamps
    end
    add_index :canvas_edges, [:source_node_id, :target_node_id], unique: true
  end
end
