require "rails_helper"

RSpec.describe "API tentacle drain", type: :request do
  let(:token) { "s3cret-deploy-token" }

  def alive_session_double(id)
    instance_double(
      TentacleRuntime::Session,
      alive?: true,
      pid: 1234,
      started_at: Time.utc(2026, 4, 21, 22),
      tentacle_id: id
    )
  end

  def auth_headers(bearer = token)
    {
      "Authorization" => "Bearer #{bearer}",
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json"
    }
  end

  before do
    TentacleRuntime::SESSIONS.clear
    stub_const("ENV", ENV.to_h.merge("NEURAMD_DEPLOY_TOKEN" => token))
  end

  after { TentacleRuntime::SESSIONS.clear }

  describe "POST /api/tentacles/drain" do
    context "authorization" do
      it "rejects when no Authorization header is provided" do
        post "/api/tentacles/drain", headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("code" => "unauthorized")
      end

      it "rejects when the bearer token does not match" do
        post "/api/tentacles/drain", headers: auth_headers("wrong-token")

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to include("code" => "unauthorized")
      end

      it "returns 503 when the server has no deploy token configured" do
        stub_const("ENV", ENV.to_h.merge("NEURAMD_DEPLOY_TOKEN" => "", "NEURAMD_DEPLOY_TOKEN_FILE" => ""))

        post "/api/tentacles/drain", headers: auth_headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to include("code" => "token_not_configured")
      end

      it "falls back to NEURAMD_DEPLOY_TOKEN_FILE when the env var is blank" do
        Dir.mktmpdir do |dir|
          token_file = File.join(dir, "deploy.token")
          File.write(token_file, "file-token\n")
          stub_const("ENV", ENV.to_h.merge("NEURAMD_DEPLOY_TOKEN" => "", "NEURAMD_DEPLOY_TOKEN_FILE" => token_file))

          post "/api/tentacles/drain", headers: auth_headers("file-token")

          expect(response).to have_http_status(:ok)
        end
      end

      it "returns 403 when tentacles are disabled" do
        allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

        post "/api/tentacles/drain", headers: auth_headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with no live sessions" do
      it "responds 200 with empty alive_ids and null timestamps" do
        post "/api/tentacles/drain", headers: auth_headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body).to include(
          "mode" => "warn",
          "alive_ids" => [],
          "stopped_ids" => [],
          "warned_at" => nil,
          "deadline_at" => nil
        )
      end

      it "does not broadcast any deploy notice" do
        expect(TentacleChannel).not_to receive(:broadcast_deploy_notice)

        post "/api/tentacles/drain", headers: auth_headers
      end
    end

    context "with live sessions in warn mode" do
      let(:ids) { Array.new(2) { SecureRandom.uuid } }

      before do
        ids.each { |id| TentacleRuntime::SESSIONS[id] = alive_session_double(id) }
      end

      it "broadcasts a deploy-notice to each alive tentacle" do
        broadcasted = []
        allow(TentacleChannel).to receive(:broadcast_deploy_notice) do |tentacle_id:, deadline_at:|
          broadcasted << [tentacle_id, deadline_at]
        end

        post "/api/tentacles/drain",
          params: {notice_seconds: 45, mode: "warn"}.to_json,
          headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(broadcasted.map(&:first)).to match_array(ids)
        expect(broadcasted.map(&:last).uniq.size).to eq(1)
      end

      it "does not stop any session in warn mode" do
        allow(TentacleChannel).to receive(:broadcast_deploy_notice)
        expect(TentacleRuntime).not_to receive(:graceful_stop_all)

        post "/api/tentacles/drain",
          params: {mode: "warn"}.to_json,
          headers: auth_headers

        body = response.parsed_body
        expect(body["alive_ids"]).to match_array(ids)
        expect(body["stopped_ids"]).to eq([])
      end

      it "clamps notice_seconds into the [0, 600] range" do
        allow(TentacleChannel).to receive(:broadcast_deploy_notice)

        post "/api/tentacles/drain",
          params: {notice_seconds: 9999, mode: "warn"}.to_json,
          headers: auth_headers

        expect(response.parsed_body["notice_seconds"]).to eq(600)
      end

      it "defaults notice_seconds to 30 when the value is not a number" do
        allow(TentacleChannel).to receive(:broadcast_deploy_notice)

        post "/api/tentacles/drain",
          params: {notice_seconds: "banana", mode: "warn"}.to_json,
          headers: auth_headers

        expect(response.parsed_body["notice_seconds"]).to eq(30)
      end

      it "coerces unknown mode to warn" do
        allow(TentacleChannel).to receive(:broadcast_deploy_notice)

        post "/api/tentacles/drain",
          params: {mode: "nuke"}.to_json,
          headers: auth_headers

        expect(response.parsed_body["mode"]).to eq("warn")
      end
    end

    context "with live sessions in force mode" do
      let(:ids) { [SecureRandom.uuid] }

      before do
        ids.each { |id| TentacleRuntime::SESSIONS[id] = alive_session_double(id) }
      end

      it "broadcasts the deploy-notice AND calls graceful_stop_all" do
        broadcasts = []
        allow(TentacleChannel).to receive(:broadcast_deploy_notice) do |tentacle_id:, **|
          broadcasts << tentacle_id
        end
        expect(TentacleRuntime).to receive(:graceful_stop_all).with(grace: 10).and_return(ids)

        post "/api/tentacles/drain",
          params: {mode: "force"}.to_json,
          headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(broadcasts).to match_array(ids)
        expect(response.parsed_body["stopped_ids"]).to match_array(ids)
      end

      it "skips the notice broadcast when mode=force with notice_seconds=0" do
        expect(TentacleChannel).not_to receive(:broadcast_deploy_notice)
        expect(TentacleRuntime).to receive(:graceful_stop_all).and_return(ids)

        post "/api/tentacles/drain",
          params: {mode: "force", notice_seconds: 0}.to_json,
          headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
