class AddAlignmentToNoteTtsAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :note_tts_assets, :alignment_data, :jsonb
    add_column :note_tts_assets, :alignment_status, :string
  end
end
