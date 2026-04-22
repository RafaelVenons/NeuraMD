require "rails_helper"
require "neuramd/exporter"
require "tmpdir"

RSpec.describe Neuramd::Exporter::EventStore do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:store) { described_class.new(base_dir: @dir) }

  describe "#append" do
    it "creates the base dir on first write" do
      store.append("deploy", {"outcome" => "clear"})
      expect(Dir.exist?(@dir)).to be true
      expect(File.exist?(File.join(@dir, "deploy.jsonl"))).to be true
    end

    it "appends one JSON line per call with a recorded_at timestamp" do
      store.append("deploy", {"outcome" => "clear"})
      store.append("deploy", {"outcome" => "aborted"})

      lines = File.readlines(File.join(@dir, "deploy.jsonl"))
      expect(lines.size).to eq(2)
      parsed = lines.map { |l| JSON.parse(l) }
      expect(parsed.map { |p| p["outcome"] }).to eq(%w[clear aborted])
      expect(parsed).to all(include("recorded_at"))
    end

    it "rejects invalid event types (path traversal, special chars)" do
      expect { store.append("../deploy", {}) }.to raise_error(ArgumentError)
      expect { store.append("deploy/x", {}) }.to raise_error(ArgumentError)
      expect { store.append("", {}) }.to raise_error(ArgumentError)
    end
  end

  describe "#read" do
    it "returns [] when the file does not exist" do
      expect(store.read("deploy")).to eq([])
    end

    it "returns parsed events in insertion order" do
      store.append("tentacle_spawn", {"tentacle_id" => "a"})
      store.append("tentacle_spawn", {"tentacle_id" => "b"})
      events = store.read("tentacle_spawn")
      expect(events.map { |e| e["tentacle_id"] }).to eq(%w[a b])
    end

    it "skips malformed JSON lines silently" do
      FileUtils.mkdir_p(@dir)
      File.write(File.join(@dir, "deploy.jsonl"),
        "#{JSON.generate("outcome" => "ok")}\nnot json here\n#{JSON.generate("outcome" => "ok")}\n")
      events = store.read("deploy")
      expect(events.size).to eq(2)
    end
  end
end
