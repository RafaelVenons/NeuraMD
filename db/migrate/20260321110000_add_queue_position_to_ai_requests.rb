class AddQueuePositionToAiRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :ai_requests, :queue_position, :integer
    add_index :ai_requests, [:status, :queue_position, :created_at]

    execute <<~SQL
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC) AS position
        FROM ai_requests
      )
      UPDATE ai_requests
      SET queue_position = ranked.position
      FROM ranked
      WHERE ai_requests.id = ranked.id
    SQL

    change_column_null :ai_requests, :queue_position, false
  end

  def down
    remove_index :ai_requests, [:status, :queue_position, :created_at]
    remove_column :ai_requests, :queue_position
  end
end
