require "rails_helper"
require "neuramd/metrics"

RSpec.describe Neuramd::Metrics do
  before { described_class.reset_for_tests! }
  after { described_class.reset_for_tests! }

  def with_env(values)
    originals = values.keys.to_h { |k| [k, ENV[k]] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe ".enabled?" do
    it "is false when NEURAMD_METRICS_URL is unset" do
      with_env("NEURAMD_METRICS_URL" => nil) do
        expect(described_class.enabled?).to be false
      end
    end

    it "is false when NEURAMD_METRICS_URL is blank/whitespace" do
      with_env("NEURAMD_METRICS_URL" => "   ") do
        expect(described_class.enabled?).to be false
      end
    end

    it "is true when NEURAMD_METRICS_URL is set" do
      with_env("NEURAMD_METRICS_URL" => "http://127.0.0.1:9100") do
        expect(described_class.enabled?).to be true
      end
    end
  end

  describe ".emit" do
    it "returns nil without spawning a thread when disabled" do
      with_env("NEURAMD_METRICS_URL" => nil) do
        expect(Thread).not_to receive(:new)
        expect(described_class.emit("deploy", outcome: "clear")).to be_nil
      end
    end

    it "POSTs JSON to /event/:type with the bearer token header" do
      with_env(
        "NEURAMD_METRICS_URL" => "http://127.0.0.1:9100",
        "NEURAMD_DEPLOY_TOKEN" => "secret",
        "NEURAMD_DEPLOY_TOKEN_FILE" => nil
      ) do
        captured = {}
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |req| captured[:request] = req; double(code: "204") }
        allow(Net::HTTP).to receive(:start).and_yield(http)

        thread = described_class.emit("deploy", outcome: "clear", extra: "data")
        thread&.join

        req = captured[:request]
        expect(req.path).to eq("/event/deploy")
        expect(req["Content-Type"]).to eq("application/json")
        expect(req["Authorization"]).to eq("Bearer secret")
        expect(JSON.parse(req.body)).to eq({"outcome" => "clear", "extra" => "data"})
      end
    end

    it "omits the Authorization header when no token is configured" do
      with_env(
        "NEURAMD_METRICS_URL" => "http://127.0.0.1:9100",
        "NEURAMD_DEPLOY_TOKEN" => nil,
        "NEURAMD_DEPLOY_TOKEN_FILE" => nil
      ) do
        captured = {}
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |req| captured[:request] = req; double(code: "204") }
        allow(Net::HTTP).to receive(:start).and_yield(http)

        described_class.emit("deploy", outcome: "clear")&.join

        expect(captured[:request]["Authorization"]).to be_nil
      end
    end

    it "reads token from file when NEURAMD_DEPLOY_TOKEN is unset" do
      Dir.mktmpdir do |dir|
        token_file = File.join(dir, "token")
        File.write(token_file, "from-file\n")

        with_env(
          "NEURAMD_METRICS_URL" => "http://127.0.0.1:9100",
          "NEURAMD_DEPLOY_TOKEN" => nil,
          "NEURAMD_DEPLOY_TOKEN_FILE" => token_file
        ) do
          captured = {}
          http = instance_double(Net::HTTP)
          allow(http).to receive(:request) { |req| captured[:request] = req; double(code: "204") }
          allow(Net::HTTP).to receive(:start).and_yield(http)

          described_class.emit("deploy")&.join

          expect(captured[:request]["Authorization"]).to eq("Bearer from-file")
        end
      end
    end

    it "does not raise when the HTTP call fails — errors are logged and swallowed" do
      with_env(
        "NEURAMD_METRICS_URL" => "http://127.0.0.1:9999",
        "NEURAMD_DEPLOY_TOKEN" => "secret",
        "NEURAMD_DEPLOY_TOKEN_FILE" => nil
      ) do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
        allow(Rails.logger).to receive(:warn)

        expect { described_class.emit("deploy")&.join }.not_to raise_error
        expect(Rails.logger).to have_received(:warn).with(/emit\(deploy\) failed/)
      end
    end

    it "uses a single persistent worker thread across many emits instead of one per call" do
      with_env(
        "NEURAMD_METRICS_URL" => "http://127.0.0.1:9100",
        "NEURAMD_DEPLOY_TOKEN" => "secret",
        "NEURAMD_DEPLOY_TOKEN_FILE" => nil
      ) do
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request).and_return(double(code: "204"))
        allow(Net::HTTP).to receive(:start).and_yield(http)

        handles = 20.times.map { described_class.emit("deploy", i: _1) }
        handles.each { |h| h&.join(2) }

        expect(described_class.worker_count).to eq(1)
      end
    end

    it "drops events and increments drop_count when the bounded queue is full" do
      with_env(
        "NEURAMD_METRICS_URL" => "http://127.0.0.1:9100",
        "NEURAMD_DEPLOY_TOKEN" => "secret",
        "NEURAMD_DEPLOY_TOKEN_FILE" => nil
      ) do
        stub_const("Neuramd::Metrics::QUEUE_CAPACITY", 2)
        allow(Rails.logger).to receive(:warn)

        gate = Queue.new
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do
          gate.pop
          double(code: "204")
        end
        allow(Net::HTTP).to receive(:start).and_yield(http)

        first = described_class.emit("deploy", n: 1)
        # Give worker time to pop the first job so it sits blocked on gate.pop.
        sleep 0.05
        full1 = described_class.emit("deploy", n: 2)
        full2 = described_class.emit("deploy", n: 3)
        dropped_a = described_class.emit("deploy", n: 4)
        dropped_b = described_class.emit("deploy", n: 5)

        expect(described_class.drop_count).to eq(2)
        # Dropped handles should be pre-signaled so callers never hang.
        expect(dropped_a.join(0.1)).not_to be_nil
        expect(dropped_b.join(0.1)).not_to be_nil

        # Drain: release the gate and let the worker finish the queued jobs.
        5.times { gate.push(:go) }
        [first, full1, full2].each { |h| h&.join(2) }
        expect(Rails.logger).to have_received(:warn).with(/dropped/).at_least(:once)
      end
    end

    it "reset_for_tests! tears down the worker and resets drop_count" do
      with_env("NEURAMD_METRICS_URL" => "http://127.0.0.1:9100") do
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request).and_return(double(code: "204"))
        allow(Net::HTTP).to receive(:start).and_yield(http)

        described_class.emit("deploy")&.join(2)
        expect(described_class.worker_count).to eq(1)

        described_class.reset_for_tests!
        expect(described_class.worker_count).to eq(0)
        expect(described_class.drop_count).to eq(0)
      end
    end
  end
end
