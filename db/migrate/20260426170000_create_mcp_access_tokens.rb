class CreateMcpAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_access_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :token_hash, null: false
      t.string :scopes, array: true, default: [], null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :mcp_access_tokens, :token_hash, unique: true
    add_index :mcp_access_tokens, :revoked_at
  end
end
