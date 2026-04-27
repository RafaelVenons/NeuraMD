class AddAgentNoteIdToMcpAccessTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :mcp_access_tokens, :agent_note,
      type: :uuid,
      foreign_key: { to_table: :notes, on_delete: :nullify },
      null: true
  end
end
