class CreatePropertyDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :property_definitions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :key,         null: false
      t.string  :value_type,  null: false
      t.string  :label
      t.string  :description
      t.jsonb   :config,      null: false, default: {}
      t.boolean :system,      null: false, default: false
      t.boolean :archived,    null: false, default: false
      t.integer :position,    null: false, default: 0
      t.timestamps
    end

    add_index :property_definitions, :key, unique: true
  end
end
