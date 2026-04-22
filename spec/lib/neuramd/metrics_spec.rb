require "rails_helper"
require "neuramd/metrics"

RSpec.describe Neuramd::Metrics do
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
  end
end
