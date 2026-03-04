class CreateAiRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_requests, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :note_revision, null: false,
        foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.string :capability, null: false  # suggest | rewrite | grammar_review | tts
      t.string :request_hash
      t.text :prompt_summary
      t.text :response_summary
      t.integer :tokens_in
      t.integer :tokens_out
      t.decimal :cost_estimate, precision: 10, scale: 6

      t.timestamps
    end

    add_index :ai_requests, :created_at
  end
end
