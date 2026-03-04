class CreateNoteLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :note_links, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :src_note, null: false, foreign_key: {to_table: :notes}, type: :uuid
      t.references :dst_note, null: false, foreign_key: {to_table: :notes}, type: :uuid
      t.string :hier_role  # target_is_parent | target_is_child | same_level | NULL
      t.references :created_in_revision, null: false,
        foreign_key: {to_table: :note_revisions}, type: :uuid
      t.jsonb :context, default: {}

      t.timestamps
    end

    # Compound unique index — prevents duplicate links between same pair
    add_index :note_links, [:src_note_id, :dst_note_id], unique: true
    add_index :note_links, :hier_role
  end
end
