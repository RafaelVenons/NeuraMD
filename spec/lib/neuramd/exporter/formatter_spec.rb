require "rails_helper"
require "neuramd/exporter"

RSpec.describe Neuramd::Exporter::Formatter do
  describe ".format" do
    it "emits help + type + value lines for a single unlabeled gauge" do
      out = described_class.format([
        {name: "neuramd_note_count", type: "gauge", help: "Total notes.", samples: [{value: 42}]}
      ])

      expect(out).to include("# HELP neuramd_note_count Total notes.")
      expect(out).to include("# TYPE neuramd_note_count gauge")
      expect(out).to include("neuramd_note_count 42.0")
      expect(out).to end_with("\n")
    end

    it "sorts labels deterministically and escapes special chars" do
      out = described_class.format([
        {
          name: "neuramd_deploy_count_total",
          type: "counter",
          help: "By outcome.",
          samples: [{labels: {outcome: "cl\"ear", host: "airch"}, value: 3}]
        }
      ])

      expect(out).to match(/neuramd_deploy_count_total\{host="airch",outcome="cl\\"ear"\} 3\.0/)
    end

    it "emits a zero sample for a metric with no samples so the series appears in Prometheus" do
      out = described_class.format([
        {name: "neuramd_tentacles_spawned_total", type: "counter", help: "...", samples: []}
      ])

      expect(out).to include("neuramd_tentacles_spawned_total 0")
    end

    it "formats infinite and NaN values sanely" do
      out = described_class.format([
        {name: "m", type: "gauge", help: "h", samples: [{value: Float::INFINITY}, {value: Float::NAN}, {value: nil}]}
      ])

      expect(out).to include("m +Inf")
      expect(out).to include("m NaN")
    end
  end
end
