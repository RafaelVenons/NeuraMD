class CreateLinkTags < ActiveRecord::Migration[8.1]
  def change
    create_table :link_tags, id: false do |t|
      t.references :note_link, null: false, foreign_key: true, type: :uuid
      t.references :tag, null: false, foreign_key: true, type: :uuid
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :link_tags, [:note_link_id, :tag_id], unique: true
  end
end
