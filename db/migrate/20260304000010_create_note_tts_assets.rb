class CreateNoteTtsAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :note_tts_assets, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :note_revision, null: false,
        foreign_key: true, type: :uuid
      t.string :language, null: false
      t.string :voice, null: false
      t.string :provider, null: false  # elevenlabs | fish_audio | openai
      t.string :model
      t.string :format, null: false, default: "mp3"
      t.string :text_sha256, null: false
      t.string :settings_hash, null: false
      t.integer :duration_ms
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    # Cache key uniqueness: same text + settings → reuse asset
    add_index :note_tts_assets,
      [:text_sha256, :language, :voice, :provider, :model, :settings_hash, :is_active],
      name: "index_note_tts_assets_on_cache_key"
  end
end
