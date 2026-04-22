require "rails_helper"
require "neuramd/exporter"
require "tmpdir"

RSpec.describe Neuramd::Exporter::Collectors::Deploy do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:store) { Neuramd::Exporter::EventStore.new(base_dir: @dir) }
  let(:collector) { described_class.new(event_store: store) }

  it "emits zeros for all known outcomes when there are no events" do
    metric = collector.collect.first
    expect(metric[:name]).to eq("neuramd_deploy_count_total")
    expect(metric[:type]).to eq("counter")
    described_class::KNOWN_OUTCOMES.each do |outcome|
      sample = metric[:samples].find { |s| s[:labels][:outcome] == outcome }
      expect(sample).not_to be_nil
      expect(sample[:value]).to eq(0)
    end
  end

  it "counts recorded events grouped by outcome" do
    store.append("deploy", {"outcome" => "clear"})
    store.append("deploy", {"outcome" => "clear"})
    store.append("deploy", {"outcome" => "aborted"})

    metric = collector.collect.first
    by_outcome = metric[:samples].to_h { |s| [s[:labels][:outcome], s[:value]] }
    expect(by_outcome["clear"]).to eq(2)
    expect(by_outcome["aborted"]).to eq(1)
    expect(by_outcome["drained"]).to eq(0)
  end

  it "ignores events that are missing an outcome" do
    store.append("deploy", {"outcome" => "clear"})
    store.append("deploy", {"unrelated" => "value"})

    metric = collector.collect.first
    by_outcome = metric[:samples].to_h { |s| [s[:labels][:outcome], s[:value]] }
    expect(by_outcome["clear"]).to eq(1)
    expect(by_outcome.values.sum).to eq(1)
  end
end
