require "rails_helper"
require "neuramd/exporter"
require "tmpdir"

RSpec.describe Neuramd::Exporter::Collectors::Tentacles do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:store) { Neuramd::Exporter::EventStore.new(base_dir: @dir) }
  let(:collector) { described_class.new(event_store: store) }

  def by_labels(metric, key)
    metric[:samples].to_h { |s| [s[:labels][key], s[:value]] }
  end

  it "returns three counter metrics" do
    metrics = collector.collect
    expect(metrics.map { |m| m[:name] }).to eq([
      "neuramd_tentacles_spawned_total",
      "neuramd_tentacles_exited_total",
      "neuramd_transcripts_persisted_total"
    ])
    expect(metrics.map { |m| m[:type] }).to all(eq("counter"))
  end

  it "counts spawn events as an unlabeled total" do
    3.times { store.append("tentacle_spawn", {"tentacle_id" => SecureRandom.uuid}) }

    metric = collector.collect.find { |m| m[:name] == "neuramd_tentacles_spawned_total" }
    expect(metric[:samples].size).to eq(1)
    expect(metric[:samples].first[:value]).to eq(3)
  end

  it "groups exit events by reason, buckets unknowns as 'unknown'" do
    store.append("tentacle_exit", {"reason" => "graceful"})
    store.append("tentacle_exit", {"reason" => "graceful"})
    store.append("tentacle_exit", {"reason" => "crash"})
    store.append("tentacle_exit", {})  # missing reason

    metric = collector.collect.find { |m| m[:name] == "neuramd_tentacles_exited_total" }
    counts = by_labels(metric, :reason)
    expect(counts["graceful"]).to eq(2)
    expect(counts["crash"]).to eq(1)
    expect(counts["unknown"]).to eq(1)
    expect(counts["forced"]).to eq(0)
  end

  it "groups transcript_persist events by outcome" do
    store.append("transcript_persist", {"outcome" => "ok"})
    store.append("transcript_persist", {"outcome" => "error"})
    store.append("transcript_persist", {"outcome" => "ok"})

    metric = collector.collect.find { |m| m[:name] == "neuramd_transcripts_persisted_total" }
    counts = by_labels(metric, :outcome)
    expect(counts["ok"]).to eq(2)
    expect(counts["error"]).to eq(1)
  end
end
