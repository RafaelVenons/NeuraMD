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
    it "lists all 23 tools" do
      response = send_request(server, method: "tools/list")
      tools = response[:result][:tools]

      expect(tools.length).to eq(23)
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly(
        "search_notes", "read_note", "list_tags", "notes_by_tag", "note_graph",
        "recent_changes", "create_note", "update_note", "patch_note", "manage_property",
        "import_markdown", "merge_notes", "find_anemic_notes", "bulk_remove_tag",
        "send_agent_message", "read_agent_inbox", "spawn_child_tentacle", "route_human_to",
        "activate_tentacle_session", "talk_to_agent", "read_my_inbox",
        "acervo_snapshot", "agent_status"
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

    it "calls patch_note and edits a section" do
      body = "# Intro\n\ntexto\n\n## Tarefas\n\n- a\n"
      patched = create(:note, title: "Nota patch")
      Notes::CheckpointService.call(note: patched, content: body, author: nil, accepted_ai_request: nil)

      response = send_request(server,
        method: "tools/call",
        params: {name: "patch_note", arguments: {
          slug: patched.slug, heading: "Tarefas", operation: "append", content: "- b"
        }})

      content = JSON.parse(response[:result][:content].first[:text])
      expect(content["patched"]).to be true
      md = patched.reload.head_revision.content_markdown
      expect(md).to match(/- a.*- b/m)
    end

    it "calls manage_property set and get" do
      create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft published]})

      set_response = send_request(server,
        method: "tools/call",
        params: {name: "manage_property", arguments: {
          slug: note.slug, operation: "set", key: "status", value: '"draft"'
        }})
      expect(JSON.parse(set_response[:result][:content].first[:text])["value"]).to eq("draft")

      get_response = send_request(server,
        method: "tools/call",
        params: {name: "manage_property", arguments: {
          slug: note.slug, operation: "get", key: "status"
        }})
      expect(JSON.parse(get_response[:result][:content].first[:text])["value"]).to eq("draft")
    end

    it "calls recent_changes and returns the note" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "recent_changes", arguments: {limit: 5}})

      content = JSON.parse(response[:result][:content].first[:text])
      slugs = content["notes"].map { |n| n["slug"] }
      expect(slugs).to include(note.slug)
    end

    it "returns error for unknown tool" do
      response = send_request(server,
        method: "tools/call",
        params: {name: "nonexistent_tool", arguments: {}})

      expect(response[:error]).to be_present
    end
  end
end
