require "rails_helper"

RSpec.describe Tasks::Protocol do
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

  let(:note) { create(:note, :with_head_revision, title: "Iniciativa A") }

  describe ".can_assign?" do
    it "lets the gerente assign to anyone" do
      expect(described_class.can_assign?("gerente", "rubi")).to be true
      expect(described_class.can_assign?("gerente", "uxui")).to be true
    end

    it "lets devops assign to its known sub-agents only" do
      expect(described_class.can_assign?("devops", "sentinela-de-deploy")).to be true
      expect(described_class.can_assign?("devops", "uxui")).to be false
    end

    it "rejects unknown callers" do
      expect(described_class.can_assign?("rando", "rubi")).to be false
      expect(described_class.can_assign?("", "rubi")).to be false
      expect(described_class.can_assign?(nil, "rubi")).to be false
    end

    it "rejects blank target" do
      expect(described_class.can_assign?("gerente", "")).to be false
    end
  end

  describe ".assign" do
    it "writes claimed_by/claimed_at/claim_authority and creates a checkpoint" do
      expect {
        described_class.assign(note: note, agent_slug: "rubi", claim_authority: "gerente")
      }.to change { note.note_revisions.count }.by(1)

      props = note.reload.current_properties
      expect(props["claimed_by"]).to eq("rubi")
      expect(props["claim_authority"]).to eq("gerente")
      expect(props["claimed_at"]).to be_a(String)
      expect { Time.iso8601(props["claimed_at"]) }.not_to raise_error
    end

    it "stores queue_after when provided" do
      described_class.assign(note: note, agent_slug: "rubi", claim_authority: "gerente", queue_after: "outra-iniciativa")
      expect(note.reload.current_properties["queue_after"]).to eq("outra-iniciativa")
    end

    it "raises Unauthorized when caller is not in DELEGATION_MAP" do
      expect {
        described_class.assign(note: note, agent_slug: "rubi", claim_authority: "rando")
      }.to raise_error(described_class::Unauthorized, /not authorized/)
    end

    it "raises Unauthorized when delegated parent tries to assign outside its scope" do
      expect {
        described_class.assign(note: note, agent_slug: "rubi", claim_authority: "devops")
      }.to raise_error(described_class::Unauthorized)
    end

    it "raises Unauthorized when claim_authority is blank" do
      expect {
        described_class.assign(note: note, agent_slug: "rubi", claim_authority: "")
      }.to raise_error(described_class::Unauthorized, /claim_authority cannot be blank/)
    end

    it "raises Unauthorized when agent_slug is blank" do
      expect {
        described_class.assign(note: note, agent_slug: "", claim_authority: "gerente")
      }.to raise_error(described_class::Unauthorized, /agent_slug cannot be blank/)
    end

    it "clears any previous closed_at/closed_status when re-assigning" do
      described_class.assign(note: note, agent_slug: "rubi", claim_authority: "gerente")
      described_class.release(note: note.reload, status: "completed", caller_slug: "rubi")
      expect(note.reload.current_properties["closed_status"]).to eq("completed")

      described_class.assign(note: note.reload, agent_slug: "uxui", claim_authority: "gerente")
      props = note.reload.current_properties
      expect(props["claimed_by"]).to eq("uxui")
      expect(props["closed_at"]).to be_nil
      expect(props["closed_status"]).to be_nil
    end
  end

  describe ".release" do
    before { described_class.assign(note: note, agent_slug: "rubi", claim_authority: "gerente") }

    it "marks completed with closed_at + closed_status" do
      described_class.release(note: note.reload, status: "completed", caller_slug: "rubi")

      props = note.reload.current_properties
      expect(props["closed_status"]).to eq("completed")
      expect(props["closed_at"]).to be_a(String)
      expect(props["claimed_by"]).to eq("rubi") # claimed_by stays for history
    end

    it "marks abandoned" do
      described_class.release(note: note.reload, status: "abandoned", caller_slug: "rubi")
      expect(note.reload.current_properties["closed_status"]).to eq("abandoned")
    end

    it "re-claims to handoff_to on handed_off, leaving the task open under new ownership" do
      described_class.release(note: note.reload, status: "handed_off", caller_slug: "rubi", handoff_to: "uxui")

      props = note.reload.current_properties
      expect(props["claimed_by"]).to eq("uxui")
      expect(props["claim_authority"]).to eq("rubi") # caller becomes the authority of the handoff
      expect(props["closed_at"]).to be_nil
      expect(props["closed_status"]).to be_nil
    end

    it "raises InvalidStatus when handed_off lacks handoff_to" do
      expect {
        described_class.release(note: note.reload, status: "handed_off", caller_slug: "rubi", handoff_to: "")
      }.to raise_error(described_class::InvalidStatus, /handoff_to/)
    end

    it "raises InvalidStatus on unknown status" do
      expect {
        described_class.release(note: note.reload, status: "ghosted", caller_slug: "rubi")
      }.to raise_error(described_class::InvalidStatus)
    end

    it "raises Unauthorized when caller is not the current claimed_by" do
      expect {
        described_class.release(note: note.reload, status: "completed", caller_slug: "uxui")
      }.to raise_error(described_class::Unauthorized, /only the current claimed_by/)
    end

    it "raises NotClaimed when the note has no claimed_by" do
      blank = create(:note, :with_head_revision, title: "Sem dono")
      expect {
        described_class.release(note: blank, status: "completed", caller_slug: "anyone")
      }.to raise_error(described_class::NotClaimed)
    end
  end

  describe ".my_tasks" do
    it "returns notes claimed by the agent and not yet closed, ordered by claimed_at desc" do
      first = create(:note, :with_head_revision, title: "First")
      second = create(:note, :with_head_revision, title: "Second")
      closed = create(:note, :with_head_revision, title: "Closed")

      described_class.assign(note: first, agent_slug: "rubi", claim_authority: "gerente")
      sleep 0.01 # ensure claimed_at ordering is monotonic
      described_class.assign(note: second, agent_slug: "rubi", claim_authority: "gerente")
      described_class.assign(note: closed, agent_slug: "rubi", claim_authority: "gerente")
      described_class.release(note: closed.reload, status: "completed", caller_slug: "rubi")

      tasks = described_class.my_tasks(agent_slug: "rubi")
      expect(tasks.map(&:slug)).to eq([second.slug, first.slug])
      expect(tasks.map(&:slug)).not_to include(closed.slug)
    end

    it "isolates tasks per agent" do
      mine = create(:note, :with_head_revision, title: "Mine")
      yours = create(:note, :with_head_revision, title: "Yours")
      described_class.assign(note: mine, agent_slug: "rubi", claim_authority: "gerente")
      described_class.assign(note: yours, agent_slug: "uxui", claim_authority: "gerente")

      expect(described_class.my_tasks(agent_slug: "rubi").map(&:slug)).to eq([mine.slug])
      expect(described_class.my_tasks(agent_slug: "uxui").map(&:slug)).to eq([yours.slug])
    end

    it "honors the limit" do
      3.times do |i|
        n = create(:note, :with_head_revision, title: "Note #{i}")
        described_class.assign(note: n, agent_slug: "rubi", claim_authority: "gerente")
      end

      expect(described_class.my_tasks(agent_slug: "rubi", limit: 2).size).to eq(2)
    end
  end

  describe ".task_history" do
    it "returns closed tasks ordered by closed_at desc" do
      a = create(:note, :with_head_revision, title: "A")
      b = create(:note, :with_head_revision, title: "B")
      open = create(:note, :with_head_revision, title: "Open")
      described_class.assign(note: a, agent_slug: "rubi", claim_authority: "gerente")
      described_class.assign(note: b, agent_slug: "rubi", claim_authority: "gerente")
      described_class.assign(note: open, agent_slug: "rubi", claim_authority: "gerente")

      described_class.release(note: a.reload, status: "completed", caller_slug: "rubi")
      sleep 0.01
      described_class.release(note: b.reload, status: "abandoned", caller_slug: "rubi")

      history = described_class.task_history(agent_slug: "rubi")
      expect(history.map(&:slug)).to eq([b.slug, a.slug])
      expect(history.map(&:slug)).not_to include(open.slug)
    end
  end
end
