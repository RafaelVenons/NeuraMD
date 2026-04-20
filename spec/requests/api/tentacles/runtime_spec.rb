require "rails_helper"

RSpec.describe "API tentacles runtime", type: :request do
  let(:user) { create(:user) }

  def make_note(title = "Tentacle")
    create(:note, title: title).tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "body")
      n.update_columns(head_revision_id: rev.id)
    end
  end

  before do
    TentacleRuntime::SESSIONS.clear
  end

  after do
    TentacleRuntime::SESSIONS.clear
  end

  describe "GET /api/tentacles/runtime" do
    it "returns 401 in the shared envelope when signed out" do
      get "/api/tentacles/runtime", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns an empty alive_ids array when no sessions exist" do
      sign_in user
      get "/api/tentacles/runtime"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"alive_ids" => []})
    end

    it "returns only alive session ids that map to active notes" do
      sign_in user
      alive_note = make_note("Alive")
      dead_note = make_note("Dead")
      orphan_id = SecureRandom.uuid

      alive_session = instance_double(TentacleRuntime::Session, alive?: true)
      dead_session = instance_double(TentacleRuntime::Session, alive?: false)
      orphan_session = instance_double(TentacleRuntime::Session, alive?: true)

      TentacleRuntime::SESSIONS[alive_note.id] = alive_session
      TentacleRuntime::SESSIONS[dead_note.id] = dead_session
      TentacleRuntime::SESSIONS[orphan_id] = orphan_session

      get "/api/tentacles/runtime"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["alive_ids"]).to contain_exactly(alive_note.id)
    end

    it "returns forbidden envelope when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      get "/api/tentacles/runtime"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("code" => "forbidden")
    end
  end
end
