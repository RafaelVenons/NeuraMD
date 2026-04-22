require "rails_helper"
require "neuramd/exporter"

RSpec.describe Neuramd::Exporter::Collectors::Notes do
  let(:collector) { described_class.new }

  it "reports the 3 expected metrics with gauge type" do
    metrics = collector.collect
    names = metrics.map { |m| m[:name] }
    expect(names).to contain_exactly(
      "neuramd_note_count",
      "neuramd_note_deleted_count",
      "neuramd_agent_messages_pending"
    )
    expect(metrics.map { |m| m[:type] }).to all(eq("gauge"))
  end

  it "reflects the current AR state at collection time" do
    active_scope = double(count: 12)
    where_not_scope = double(count: 3)
    where_relation = double(not: where_not_scope)
    pending_scope = double(count: 5)

    allow(Note).to receive(:active).and_return(active_scope)
    allow(Note).to receive(:where).and_return(where_relation)
    allow(AgentMessage).to receive(:where).with(delivered_at: nil).and_return(pending_scope)

    metrics = collector.collect.to_h { |m| [m[:name], m[:samples].first[:value]] }
    expect(metrics["neuramd_note_count"]).to eq(12)
    expect(metrics["neuramd_note_deleted_count"]).to eq(3)
    expect(metrics["neuramd_agent_messages_pending"]).to eq(5)
  end
end
