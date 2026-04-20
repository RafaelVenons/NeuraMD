require "rails_helper"

RSpec.describe "API tentacle sessions index", type: :request do
  let(:user) { create(:user) }

  def make_note(title)
    create(:note, title: title).tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "body")
      n.update_columns(head_revision_id: rev.id)
    end
  end

  before  { TentacleRuntime::SESSIONS.clear }
  after   { TentacleRuntime::SESSIONS.clear }

  describe "GET /api/tentacles/sessions" do
    it "returns 401 envelope when signed out" do
      get "/api/tentacles/sessions", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns an empty list when there are no sessions" do
      sign_in user
      get "/api/tentacles/sessions"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"sessions" => []})
    end

    it "returns alive sessions bound to active notes, newest first" do
      sign_in user
      older_note = make_note("Older")
      newer_note = make_note("Newer")
      dead_note  = make_note("Dead")

      older = instance_double(
        TentacleRuntime::Session, alive?: true, pid: 101,
        started_at: Time.utc(2026, 4, 19, 12)
      )
      newer = instance_double(
        TentacleRuntime::Session, alive?: true, pid: 202,
        started_at: Time.utc(2026, 4, 20, 8)
      )
      dead = instance_double(
        TentacleRuntime::Session, alive?: false, pid: 303,
        started_at: Time.utc(2026, 4, 20, 9)
      )
      allow(older).to receive(:instance_variable_get).with(:@command).and_return(%w[bash -l])
      allow(newer).to receive(:instance_variable_get).with(:@command).and_return(%w[claude])
      allow(dead).to receive(:instance_variable_get).with(:@command).and_return(%w[bash -l])

      TentacleRuntime::SESSIONS[older_note.id] = older
      TentacleRuntime::SESSIONS[newer_note.id] = newer
      TentacleRuntime::SESSIONS[dead_note.id]  = dead

      get "/api/tentacles/sessions"

      body = response.parsed_body["sessions"]
      expect(body.map { |s| s["tentacle_id"] }).to eq([newer_note.id, older_note.id])
      expect(body.first).to include(
        "slug" => newer_note.slug,
        "title" => "Newer",
        "alive" => true,
        "pid" => 202,
        "command" => %w[claude]
      )
    end

    it "drops sessions whose note has been soft-deleted" do
      sign_in user
      note = make_note("Ghost")
      note.update!(deleted_at: Time.current)
      session = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      allow(session).to receive(:instance_variable_get).with(:@command).and_return(%w[bash])
      TentacleRuntime::SESSIONS[note.id] = session

      get "/api/tentacles/sessions"

      expect(response.parsed_body["sessions"]).to eq([])
    end

    it "returns forbidden envelope when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      get "/api/tentacles/sessions"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("code" => "forbidden")
    end
  end
end
