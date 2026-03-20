class AddAsyncFieldsToAiRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_requests, :status, :string, null: false, default: "queued"
    add_column :ai_requests, :requested_provider, :string
    add_column :ai_requests, :model, :string
    add_column :ai_requests, :input_text, :text
    add_column :ai_requests, :output_text, :text
    add_column :ai_requests, :error_message, :text
    add_column :ai_requests, :metadata, :jsonb, null: false, default: {}
    add_column :ai_requests, :started_at, :datetime
    add_column :ai_requests, :completed_at, :datetime

    add_index :ai_requests, :status
    add_index :ai_requests, :requested_provider
  end
end
