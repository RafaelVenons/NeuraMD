require "rails_helper"
require "mcp"

RSpec.describe "MCP Server boot" do
  it "creates an MCP::Server without error" do
    server = MCP::Server.new(name: "neuramd", tools: [])
    expect(server).to be_a(MCP::Server)
    expect(server.name).to eq("neuramd")
  end

  it "has access to ActiveRecord models" do
    expect(Note).to be < ApplicationRecord
    expect(Tag).to be < ApplicationRecord
    expect(NoteLink).to be < ApplicationRecord
  end

  it "registers all NeuraMD tools" do
    tools = Mcp::Tools.all
    expect(tools).to be_an(Array)
    expect(tools.length).to eq(14)
    expect(tools.map(&:name_value)).to contain_exactly(
      "search_notes", "read_note", "list_tags", "notes_by_tag", "note_graph",
      "recent_changes", "create_note", "update_note", "patch_note", "manage_property",
      "import_markdown", "merge_notes", "find_anemic_notes", "bulk_remove_tag"
    )
  end

  it "builds a server with all tools" do
    server = MCP::Server.new(name: "neuramd", tools: Mcp::Tools.all)
    response = server.handle({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/list",
      params: {}
    })
    result = response[:result]
    expect(result[:tools].length).to eq(14)
  end
end
