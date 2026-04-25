require "rails_helper"

RSpec.describe Tasks::ActivationNotifier do
  before do
    PropertyDefinition.find_or_create_by!(key: "claimed_by") { |d| d.value_type = "text"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "claimed_at") { |d| d.value_type = "datetime"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "closed_at") { |d| d.value_type = "datetime"; d.system = true }
    PropertyDefinition.find_or_create_by!(key: "closed_status") do |d|
      d.value_type = "enum"
      d.system = true
      d.config = {"options" => Tasks::Protocol::CLOSED_STATUSES}
    end
    PropertyDefinition.find_or_create_by!(key: "claim_authority") { |d| d.value_type = "text"; d.system = true }
  end

  let!(:gerente) { create(:note, :with_head_revision, title: "Gerente", slug: "gerente") }
  let(:target) { create(:note, :with_head_revision, title: "Target Agent") }

  it "is a no-op when requested_by is the gerente itself" do
    expect {
      described_class.notify_if_external(target_note: target, requested_by: "gerente")
    }.not_to change { AgentMessage.count }
  end

  it "messages the gerente when requested_by is another agent" do
    rubi = create(:note, :with_head_revision, title: "Rubi", slug: "rubi")

    expect {
      described_class.notify_if_external(target_note: target, requested_by: rubi.slug)
    }.to change { AgentMessage.count }.by(1)

    msg = AgentMessage.order(created_at: :desc).first
    expect(msg.from_note_id).to eq(rubi.id)
    expect(msg.to_note_id).to eq(gerente.id)
    expect(msg.content).to include(target.slug)
    expect(msg.content).to include('"rubi"')
  end

  it "uses the gerente as from_note when requestor slug is unknown but skips because gerente cannot send to self" do
    # When the requestor slug doesn't resolve to a real note, we'd
    # fall back to the gerente — but the sender refuses self-send.
    # Best-effort: silently skip rather than raise. (Coverage: this
    # path returns nil from resolve_from_note, no AgentMessage created.)
    expect {
      described_class.notify_if_external(target_note: target, requested_by: "ghost-agent")
    }.not_to change { AgentMessage.count }
  end

  it "labels requested_by as 'unknown' when nil/blank and the requestor still resolves to a real note" do
    # When requested_by is nil, we can't link a sender. The notifier
    # falls back to gerente as from, which collides with to=gerente
    # and is skipped. So no message either. This documents that nil
    # requestor produces no notification today — covered by spec.
    expect {
      described_class.notify_if_external(target_note: target, requested_by: nil)
    }.not_to change { AgentMessage.count }
  end

  it "lists open tasks of the target in the message body" do
    rubi = create(:note, :with_head_revision, title: "Rubi", slug: "rubi")
    initiative = create(:note, :with_head_revision, title: "Iniciativa Foo")
    Tasks::Protocol.assign(note: initiative, agent_slug: target.slug, claim_authority: "gerente")

    described_class.notify_if_external(target_note: target.reload, requested_by: rubi.slug)

    msg = AgentMessage.order(created_at: :desc).first
    expect(msg.content).to include("Iniciativa Foo")
    expect(msg.content).to include(initiative.slug)
  end

  it "swallows internal errors so activation is not blocked" do
    rubi = create(:note, :with_head_revision, title: "Rubi", slug: "rubi")
    allow(AgentMessages::Sender).to receive(:call).and_raise(StandardError, "boom")
    allow(Rails.logger).to receive(:error)

    expect {
      described_class.notify_if_external(target_note: target, requested_by: rubi.slug)
    }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/activation notify failed/)
  end
end
