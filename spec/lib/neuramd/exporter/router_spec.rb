require "rails_helper"
require "neuramd/exporter"
require "tmpdir"

RSpec.describe Neuramd::Exporter::Router do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  let(:event_store) { Neuramd::Exporter::EventStore.new(base_dir: @dir) }

  let(:fake_collector) do
    Class.new do
      def collect
        [{name: "fake_metric", type: "gauge", help: "test", samples: [{value: 7}]}]
      end
    end.new
  end

  let(:router) { described_class.new(event_store: event_store, collectors: [fake_collector]) }

  def env_for(method:, path:, body: nil, headers: {})
    rack_env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "rack.input" => StringIO.new(body.to_s)
    }
    headers.each { |k, v| rack_env[k] = v }
    rack_env
  end

  describe "GET /metrics" do
    it "renders Prometheus text format from registered collectors" do
      status, headers, body = router.call(env_for(method: "GET", path: "/metrics"))
      payload = body.join

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq(Neuramd::Exporter::Formatter::CONTENT_TYPE)
      expect(payload).to include("fake_metric 7.0")
      expect(payload).to include("# HELP fake_metric test")
    end

    it "swallows collector errors so one bad collector does not break the scrape" do
      broken = Class.new do
        def collect = raise("boom")
      end.new
      router = described_class.new(event_store: event_store, collectors: [fake_collector, broken])

      status, _, body = router.call(env_for(method: "GET", path: "/metrics"))
      expect(status).to eq(200)
      expect(body.join).to include("fake_metric 7.0")
    end

    it "rejects non-GET with 405" do
      status, = router.call(env_for(method: "POST", path: "/metrics", body: ""))
      expect(status).to eq(405)
    end
  end

  describe "GET /health" do
    it "returns 200 ok" do
      status, _, body = router.call(env_for(method: "GET", path: "/health"))
      expect(status).to eq(200)
      expect(body.join.strip).to eq("ok")
    end
  end

  describe "POST /event/:type" do
    it "appends a JSON body to the event store and returns 204" do
      status, = router.call(env_for(
        method: "POST",
        path: "/event/deploy",
        body: JSON.generate(outcome: "clear", newrev: "abc123")
      ))

      expect(status).to eq(204)
      events = event_store.read("deploy")
      expect(events.size).to eq(1)
      expect(events.first).to include("outcome" => "clear", "newrev" => "abc123")
    end

    it "accepts an empty body" do
      status, = router.call(env_for(method: "POST", path: "/event/tentacle_spawn", body: ""))
      expect(status).to eq(204)
      expect(event_store.read("tentacle_spawn").size).to eq(1)
    end

    it "returns 400 on invalid JSON" do
      status, _, body = router.call(env_for(
        method: "POST", path: "/event/deploy", body: "{not json"
      ))
      expect(status).to eq(400)
      expect(JSON.parse(body.join)).to include("error")
    end

    it "returns 400 on malformed event type" do
      status, _, body = router.call(env_for(
        method: "POST", path: "/event/bad..type", body: "{}"
      ))
      expect(status).to eq(400)
      expect(JSON.parse(body.join)["error"]["code"]).to eq("invalid_type")
    end

    it "rejects non-POST" do
      status, = router.call(env_for(method: "GET", path: "/event/deploy"))
      expect(status).to eq(405)
    end
  end

  describe "unknown path" do
    it "returns 404" do
      status, = router.call(env_for(method: "GET", path: "/nope"))
      expect(status).to eq(404)
    end
  end
end
