require "rails_helper"
require "mcp"

# Camada 1 — covers the four MCP tools that wrap Tasks::Protocol:
# AssignTaskTool, MyTasksTool, ReleaseTaskTool, TaskHistoryTool.
RSpec.describe "Camada 1 MCP tools" do
  before do
    PropertyDefinition.find_or_create_by!(key: "claimed_by") { |d| d.value_type = "text"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "claimed_at") { |d| d.value_type = "datetime"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "closed_at") { |d| d.value_type = "datetime"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "closed_status") do |d|
      d.value_type = "enum"
      d.system = true
      d.config = {"options" => Tasks::Protocol::CLOSED_STATUSES}
    end
    PropertyDefinition.find_or_create_by!(key: "queue_after") { |d| d.value_type = "text"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "claim_authority") { |d| d.value_type = "text"; d.system = true }
  end

  let!(:note) { create(:note, :with_head_revision, title: "Iniciativa A") }

  def with_agent_env(slug)
    previous = ENV["NEURAMD_AGENT_SLUG"]
    ENV["NEURAMD_AGENT_SLUG"] = slug
    yield
  ensure
    previous.nil? ? ENV.delete("NEURAMD_AGENT_SLUG") : ENV["NEURAMD_AGENT_SLUG"] = previous
  end

  def parse(response)
    JSON.parse(response.content.first[:text])
  end

  describe Mcp::Tools::AssignTaskTool do
    it "assigns when caller is the gerente" do
      response = with_agent_env("gerente") do
        described_class.call(note_slug: note.slug, agent_slug: "rubi")
      end
      data = parse(response)

      expect(response.error?).to be_falsey
      expect(data["assigned"]).to be true
      expect(data["claimed_by"]).to eq("rubi")
      expect(data["claim_authority"]).to eq("gerente")
      expect(note.reload.current_properties["claimed_by"]).to eq("rubi")
    end

    it "rejects when caller is not authorized" do
      response = with_agent_env("rando") do
        described_class.call(note_slug: note.slug, agent_slug: "rubi")
      end

      expect(response.error?).to be_truthy
      expect(response.content.first[:text]).to start_with("403:")
    end

    it "rejects when ENV NEURAMD_AGENT_SLUG is unset (caller identity unknown)" do
      ENV.delete("NEURAMD_AGENT_SLUG")
      response = described_class.call(note_slug: note.slug, agent_slug: "rubi")
      expect(response.error?).to be_truthy
      expect(response.content.first[:text]).to include("NEURAMD_AGENT_SLUG not set")
    end

    it "returns clear error when note slug is unknown" do
      response = with_agent_env("gerente") do
        described_class.call(note_slug: "ghost-note", agent_slug: "rubi")
      end
      expect(response.error?).to be_truthy
      expect(response.content.first[:text]).to include("note not found")
    end
  end

  describe Mcp::Tools::MyTasksTool do
    before { Tasks::Protocol.assign(note: note, agent_slug: "rubi", claim_authority: "gerente") }

    it "returns the caller's open tasks when agent_slug omitted" do
      response = with_agent_env("rubi") { described_class.call }
      data = parse(response)

      expect(data["agent_slug"]).to eq("rubi")
      expect(data["count"]).to eq(1)
      expect(data["tasks"].first["slug"]).to eq(note.slug)
    end

    it "returns another agent's tasks when agent_slug given (no auth check on read)" do
      response = with_agent_env("uxui") do
        described_class.call(agent_slug: "rubi")
      end
      data = parse(response)
      expect(data["count"]).to eq(1)
    end

    it "errors when neither agent_slug nor ENV is set" do
      ENV.delete("NEURAMD_AGENT_SLUG")
      response = described_class.call
      expect(response.error?).to be_truthy
    end
  end

  describe Mcp::Tools::ReleaseTaskTool do
    before { Tasks::Protocol.assign(note: note, agent_slug: "rubi", claim_authority: "gerente") }

    it "lets the current claimed_by release with status=completed" do
      response = with_agent_env("rubi") do
        described_class.call(note_slug: note.slug, status: "completed")
      end
      data = parse(response)

      expect(data["released"]).to be true
      expect(data["closed_status"]).to eq("completed")
      expect(note.reload.current_properties["closed_status"]).to eq("completed")
    end

    it "rejects when caller is not the current claimed_by" do
      response = with_agent_env("uxui") do
        described_class.call(note_slug: note.slug, status: "completed")
      end
      expect(response.error?).to be_truthy
      expect(response.content.first[:text]).to start_with("403:")
    end

    it "performs handoff and re-claims to handoff_to" do
      response = with_agent_env("rubi") do
        described_class.call(note_slug: note.slug, status: "handed_off", handoff_to: "uxui")
      end
      data = parse(response)
      expect(data["claimed_by"]).to eq("uxui")
      expect(data["claim_authority"]).to eq("rubi")
      expect(note.reload.current_properties["claimed_by"]).to eq("uxui")
    end

    it "errors when handed_off lacks handoff_to" do
      response = with_agent_env("rubi") do
        described_class.call(note_slug: note.slug, status: "handed_off")
      end
      expect(response.error?).to be_truthy
      expect(response.content.first[:text]).to include("handoff_to")
    end
  end

  describe Mcp::Tools::TaskHistoryTool do
    before do
      a = create(:note, :with_head_revision, title: "Closed A")
      b = create(:note, :with_head_revision, title: "Open B")
      Tasks::Protocol.assign(note: a, agent_slug: "rubi", claim_authority: "gerente")
      Tasks::Protocol.assign(note: b, agent_slug: "rubi", claim_authority: "gerente")
      Tasks::Protocol.release(note: a.reload, status: "completed", caller_slug: "rubi")
    end

    it "returns only closed tasks" do
      response = with_agent_env("rubi") { described_class.call }
      data = parse(response)
      expect(data["tasks"].map { |t| t["closed_status"] }).to all(eq("completed"))
    end
  end
end
