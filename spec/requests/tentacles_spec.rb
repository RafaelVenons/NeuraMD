require "rails_helper"

RSpec.describe "Tentacles", type: :request do
  let(:user) { create(:user) }
  let!(:note) do
    create(:note, title: "Tentacle Playground").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "body")
      n.update_columns(head_revision_id: rev.id)
    end
  end

  before do
    allow(TentacleRuntime).to receive(:start).and_call_original
    allow(TentacleRuntime).to receive(:stop).and_call_original
    allow(WorktreeService).to receive(:ensure) do |tentacle_id:, **|
      path = WorktreeService.path_for(tentacle_id: tentacle_id)
      FileUtils.mkdir_p(path)
      path
    end
    allow(Tentacles::TranscriptService).to receive(:persist)
  end

  after do
    TentacleRuntime.reset!
    FileUtils.rm_rf(Rails.root.join("tmp/tentacles", note.id.to_s))
  end

  describe "GET /notes/:slug/tentacle" do
    it "redirects unauthenticated users" do
      get note_tentacle_path(note.slug)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders the terminal page when signed in" do
      sign_in user
      get note_tentacle_path(note.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-controller=\"tentacle\"")
      expect(response.body).to include(note.title)
    end

    it "wires the inbox and spawn-child panels" do
      sign_in user
      get note_tentacle_path(note.slug)

      expect(response.body).to include("data-controller=\"tentacle-inbox\"")
      expect(response.body).to include("data-tentacle-inbox-url-value")
      expect(response.body).to include("data-tentacle-inbox-deliver-url-value")
      expect(response.body).to include("nm-tentacle__spawn-form")
    end
  end

  describe "POST /notes/:slug/tentacle" do
    before { sign_in user }

    it "starts a session and returns tentacle metadata" do
      post note_tentacle_path(note.slug, format: :json),
        params: { command: "bash" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["tentacle_id"]).to eq(note.id)
      expect(body["pid"]).to be_a(Integer)
      expect(body["cwd"]).to end_with("tmp/tentacles/#{note.id}")
      expect(TentacleRuntime.get(note.id)).not_to be_nil
    end

    it "falls back to bash when an unknown command is requested" do
      post note_tentacle_path(note.slug, format: :json),
        params: { command: "rm -rf /" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["command"]).to eq(["bash", "-l"])
    end

    it "registers an on_exit callback so transcripts can be persisted" do
      expect(TentacleRuntime).to receive(:start) do |on_exit:, **kwargs|
        expect(on_exit).to respond_to(:call)
        instance_double(TentacleRuntime::Session, pid: 4242, alive?: true).tap do |session|
          allow(session).to receive(:pid).and_return(4242)
        end
      end

      post note_tentacle_path(note.slug, format: :json),
        params: { command: "bash" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /notes/:slug/tentacle" do
    before { sign_in user }

    it "stops the session" do
      post note_tentacle_path(note.slug, format: :json),
        params: { command: "bash" }.to_json,
        headers: { "Content-Type" => "application/json" }
      expect(TentacleRuntime.get(note.id)).not_to be_nil

      delete note_tentacle_path(note.slug, format: :json)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("stopped" => true)
      expect(TentacleRuntime.get(note.id)).to be_nil
    end
  end

  describe "when tentacles are disabled" do
    before do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
    end

    it "blocks GET with a redirect" do
      get note_tentacle_path(note.slug)
      expect(response).to redirect_to(root_path)
    end

    it "blocks POST with 403 JSON and does not start a session" do
      expect(TentacleRuntime).not_to receive(:start)

      post note_tentacle_path(note.slug, format: :json),
        params: { command: "bash" }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/disabled/i)
    end

    it "blocks DELETE with 403 JSON" do
      delete note_tentacle_path(note.slug, format: :json)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
