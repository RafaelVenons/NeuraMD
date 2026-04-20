class DropCanvasTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :canvas_edges, if_exists: true
    drop_table :canvas_nodes, if_exists: true
    drop_table :canvas_documents, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
