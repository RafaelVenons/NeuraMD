class AddRetryFieldsToAiRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_requests, :attempts_count, :integer, null: false, default: 0
    add_column :ai_requests, :max_attempts, :integer, null: false, default: 3
    add_column :ai_requests, :next_retry_at, :datetime
    add_column :ai_requests, :last_error_at, :datetime
    add_column :ai_requests, :last_error_kind, :string

    add_index :ai_requests, :next_retry_at
    add_index :ai_requests, :last_error_kind
  end
end
