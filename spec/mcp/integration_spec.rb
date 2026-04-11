require "rails_helper"
require "mcp"
require "open3"

RSpec.describe "MCP Server integration", type: :integration do
  let(:server) do
    MCP::Server.new(name: "neuramd", tools: Mcp::Tools.all)
  end

  def send_request(server, method:, params: {}, id: 1)
    request = {jsonrpc: "2.0", id: id, method: method, params: params}
    server.handle(request)
  end

  describe "initialize" do
    it "returns server info and capabilities" do
      response = send_request(server, method: "initialize", params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: {name: "test", version: "1.0"}
      })

      result = response[:result]
      expect(result[:serverInfo][:name]).to eq("neuramd")
      expect(result[:capabilities][:tools]).to be_present
    end
  end

  describe "tools/list" do
    it "lists all 10 tools" do
      response = send_request(server, method: "tools/list")
      tools = response[:result][:tools]

      expect(tools.length).to eq(10)
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly(
        "search_notes", "read_note", "list_tags", "notes_by_tag", "note_graph",
        "create_note", "update_note", "import_markdown", "merge_notes", "find_anemic_notes"
      )
    end

    it "includes input schemas for each tool" do
      response = send_request(server, method: "tools/list")
      tools = response[:result][:tools]

      tools.each do |tool|
        expect(tool[:inputSchema]).to be_present
        expect(tool[:description]).to be_present
      end
    end
  end

  describe "tools/call" do
    let!(:note) { create(:note, :with_head_revision, title: "Nota de integração") }
    let!(:tag) { create(:tag, name: "test-mcp") }

    before { note.tags << tag }

    it "calls search_notes and returns results" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "search_notes", arguments: {query: "integração"}})

      content = JSON.parse(response[:result][:content].first[:text])
      expect(content["notes"].first["title"]).to eq("Nota de integração")
    end

    it "calls read_note and returns full content" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "read_note", arguments: {slug: note.slug}})

      content = JSON.parse(response[:result][:content].first[:text])
      expect(content["title"]).to eq("Nota de integração")
      expect(content["tags"]).to include("test-mcp")
      expect(content).to have_key("body")
    end

    it "calls list_tags and returns all tags" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "list_tags", arguments: {}})

      content = JSON.parse(response[:result][:content].first[:text])
      names = content["tags"].map { |t| t["name"] }
      expect(names).to include("test-mcp")
    end

    it "calls notes_by_tag and filters correctly" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "notes_by_tag", arguments: {tag: "test-mcp"}})

      content = JSON.parse(response[:result][:content].first[:text])
      expect(content["notes"].length).to eq(1)
      expect(content["notes"].first["title"]).to eq("Nota de integração")
    end

    it "calls note_graph and returns neighbors" do
      target = create(:note, :with_head_revision, title: "Vizinha")
      create(:note_link,
        src_note: note, dst_note: target,
        hier_role: "target_is_child",
        created_in_revision: note.head_revision)

      response = send_request(server,
        method: "tools/call",
        params: {name: "note_graph", arguments: {slug: note.slug}})

      content = JSON.parse(response[:result][:content].first[:text])
      expect(content["center"]["title"]).to eq("Nota de integração")
      expect(content["links"].length).to eq(1)
      expect(content["links"].first["target_title"]).to eq("Vizinha")
    end

    it "returns error for unknown tool" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "nonexistent_tool", arguments: {}})

      expect(response[:error]).to be_present
    end
  end
end
