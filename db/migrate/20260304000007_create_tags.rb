class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string :name, null: false
      t.string :color_hex
      t.string :icon
      t.string :tag_scope, null: false, default: "both"  # note | link | both

      t.timestamps
    end

    add_index :tags, :name, unique: true
  end
end
