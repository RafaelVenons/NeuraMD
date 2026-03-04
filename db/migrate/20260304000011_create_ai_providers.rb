class CreateAiProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_providers, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string :name, null: false  # openai | anthropic | azure_openai | ollama | local
      t.boolean :enabled, null: false, default: false
      t.string :base_url
      t.string :default_model_text
      t.jsonb :config, default: {}

      t.timestamps
    end

    add_index :ai_providers, :name, unique: true
  end
end
