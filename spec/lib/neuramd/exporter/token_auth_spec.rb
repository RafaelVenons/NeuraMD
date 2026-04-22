require "rails_helper"
require "neuramd/exporter"

RSpec.describe Neuramd::Exporter::TokenAuth do
  let(:inner_app) do
    ->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] }
  end

  def env_for(path, auth: nil)
    e = {"PATH_INFO" => path, "REQUEST_METHOD" => "POST"}
    e["HTTP_AUTHORIZATION"] = auth if auth
    e
  end

  it "passes through /metrics and /health regardless of token" do
    middleware = described_class.new(inner_app, expected_token: "")
    expect(middleware.call(env_for("/metrics")).first).to eq(200)
    expect(middleware.call(env_for("/health")).first).to eq(200)
  end

  it "returns 503 for /event/* when no token is configured" do
    middleware = described_class.new(inner_app, expected_token: "")
    status, _, body = middleware.call(env_for("/event/deploy", auth: "Bearer anything"))
    expect(status).to eq(503)
    expect(JSON.parse(body.join)["error"]["code"]).to eq("token_not_configured")
  end

  it "returns 401 for /event/* without Authorization header" do
    middleware = described_class.new(inner_app, expected_token: "good")
    status, = middleware.call(env_for("/event/deploy"))
    expect(status).to eq(401)
  end

  it "returns 401 for /event/* with wrong token" do
    middleware = described_class.new(inner_app, expected_token: "good")
    status, = middleware.call(env_for("/event/deploy", auth: "Bearer bad"))
    expect(status).to eq(401)
  end

  it "forwards to the inner app when the token matches" do
    middleware = described_class.new(inner_app, expected_token: "good")
    status, = middleware.call(env_for("/event/deploy", auth: "Bearer good"))
    expect(status).to eq(200)
  end

  it "rejects tokens of the wrong length without timing leak" do
    middleware = described_class.new(inner_app, expected_token: "good")
    status, = middleware.call(env_for("/event/deploy", auth: "Bearer goodish"))
    expect(status).to eq(401)
  end
end
