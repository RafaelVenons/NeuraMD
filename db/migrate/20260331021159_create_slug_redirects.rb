class CreateSlugRedirects < ActiveRecord::Migration[8.1]
  def change
    create_table :slug_redirects, id: :uuid do |t|
      t.references :note, null: false, foreign_key: true, type: :uuid
      t.string :slug, null: false
      t.timestamps
    end

    add_index :slug_redirects, :slug, unique: true
  end
end
