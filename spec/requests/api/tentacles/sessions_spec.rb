require "rails_helper"

RSpec.describe "API tentacle sessions", type: :request do
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

  describe "GET /api/notes/:slug/tentacle" do
    it "returns 401 in the shared envelope when signed out" do
      note = make_note
      get "/api/notes/#{note.slug}/tentacle", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "reports alive: false with nulls when no session exists" do
      sign_in user
      note = make_note
      get "/api/notes/#{note.slug}/tentacle"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["tentacle_id"]).to eq(note.id)
      expect(body["alive"]).to eq(false)
      expect(body["pid"]).to be_nil
      expect(body["command"]).to be_nil
    end

    it "reports alive session metadata when TentacleRuntime has one" do
      sign_in user
      note = make_note("Alive")
      session = instance_double(
        TentacleRuntime::Session,
        alive?: true,
        pid: 4242,
        started_at: Time.utc(2026, 4, 20, 12),
        tentacle_id: note.id
      )
      allow(session).to receive(:instance_variable_get).with(:@command).and_return(%w[bash -l])
      TentacleRuntime::SESSIONS[note.id] = session

      get "/api/notes/#{note.slug}/tentacle"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["alive"]).to eq(true)
      expect(body["pid"]).to eq(4242)
      expect(body["command"]).to eq(%w[bash -l])
      expect(body["started_at"]).to eq("2026-04-20T12:00:00Z")
    end

    it "returns the envelope 404 when the slug is unknown" do
      sign_in user
      get "/api/notes/missing/tentacle"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end

    it "returns forbidden envelope when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
      note = make_note

      get "/api/notes/#{note.slug}/tentacle"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("code" => "forbidden")
    end
  end

  describe "POST /api/notes/:slug/tentacle" do
    it "starts a session through TentacleRuntime and returns its metadata" do
      sign_in user
      note = make_note("Start")
      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true,
        pid: 9001,
        started_at: Time.utc(2026, 4, 20, 13)
      )
      expect(TentacleRuntime).to receive(:start).with(
        hash_including(tentacle_id: note.id, command: %w[bash -l])
      ).and_return(fake)

      post "/api/notes/#{note.slug}/tentacle", params: {command: "bash"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["tentacle_id"]).to eq(note.id)
      expect(body["alive"]).to eq(true)
      expect(body["pid"]).to eq(9001)
      expect(body["command"]).to eq(%w[bash -l])
      expect(body["reused"]).to eq(false)
      expect(body["boot_config_applied"]).to eq(true)
    end

    it "falls back to bash when command is unknown" do
      sign_in user
      note = make_note("Fallback")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      expect(TentacleRuntime).to receive(:start).with(
        hash_including(command: %w[bash -l])
      ).and_return(fake)

      post "/api/notes/#{note.slug}/tentacle", params: {command: "totally-unknown"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:created)
    end

    context "when the note has tentacle boot config" do
      before do
        PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
          d.value_type = "text"
          d.system = true
        end
        PropertyDefinition.find_or_create_by!(key: "tentacle_initial_prompt") do |d|
          d.value_type = "long_text"
          d.system = true
        end
      end

      it "passes tentacle_cwd as repo_root to WorktreeService and initial_prompt to TentacleRuntime" do
        sign_in user
        note = make_note("Booted")
        Properties::SetService.call(
          note: note,
          changes: {
            "tentacle_cwd" => "/home/venom/projects/MapledaRapeize",
            "tentacle_initial_prompt" => "Você é Dev Maple. Leia o charter."
          }
        )

        fake = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 9001, started_at: Time.utc(2026, 4, 20, 14)
        )
        expect(WorktreeService).to receive(:ensure).with(
          hash_including(tentacle_id: note.id, repo_root: "/home/venom/projects/MapledaRapeize")
        ).and_return("/home/venom/projects/MapledaRapeize/tmp/tentacles/#{note.id}")
        expect(TentacleRuntime).to receive(:start).with(
          hash_including(
            tentacle_id: note.id,
            command: %w[claude],
            initial_prompt: "Você é Dev Maple. Leia o charter."
          )
        ).and_return(fake)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "defaults WorktreeService to Rails.root when tentacle_cwd is unset" do
        sign_in user
        note = make_note("NoCwd")

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(WorktreeService).to receive(:ensure) do |**kwargs|
          expect(kwargs[:tentacle_id]).to eq(note.id)
          expect([nil, Rails.root]).to include(kwargs[:repo_root])
          "/stub/worktree"
        end
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:initial_prompt]).to be_nil
          fake
        end

        post "/api/notes/#{note.slug}/tentacle", params: {command: "bash"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "omits initial_prompt when property is not set" do
        sign_in user
        note = make_note("CwdOnly")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => "/home/venom/projects/MapledaRapeize"}
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:initial_prompt]).to be_nil
          fake
        end

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "falls back to Rails.root when stored tentacle_cwd is outside the whitelist" do
        sign_in user
        note = make_note("TaintedCwd")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => "/etc"}
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(WorktreeService).to receive(:ensure) do |**kwargs|
          expect(kwargs[:repo_root]).to eq(Rails.root)
          "/stub/worktree"
        end
        allow(TentacleRuntime).to receive(:start).and_return(fake)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "bash"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "falls back to Rails.root when stored tentacle_cwd does not exist" do
        sign_in user
        note = make_note("VanishedCwd")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => "/home/venom/projects/does-not-exist-#{SecureRandom.hex(4)}"}
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(WorktreeService).to receive(:ensure) do |**kwargs|
          expect(kwargs[:repo_root]).to eq(Rails.root)
          "/stub/worktree"
        end
        allow(TentacleRuntime).to receive(:start).and_return(fake)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "bash"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "signals reused=true and skips TentacleRuntime.start when a live session already exists" do
        sign_in user
        note = make_note("LiveReuse")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_initial_prompt" => "fresh boot message"}
        )

        existing = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 4242, started_at: Time.utc(2026, 4, 20, 10)
        )
        allow(existing).to receive(:instance_variable_get).with(:@command).and_return(%w[claude])
        TentacleRuntime::SESSIONS[note.id] = existing

        expect(WorktreeService).not_to receive(:ensure)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["reused"]).to eq(true)
        expect(body["boot_config_applied"]).to eq(false)
        expect(body["pid"]).to eq(4242)
      end

      it "omits initial_prompt when stored value exceeds the 2KB cap" do
        sign_in user
        note = make_note("OversizePrompt")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_initial_prompt" => "x" * 2049}
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:initial_prompt]).to be_nil
          fake
        end

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "DELETE /api/notes/:slug/tentacle" do
    it "stops the session and returns stopped: true" do
      sign_in user
      note = make_note("Stop")
      expect(TentacleRuntime).to receive(:stop).with(tentacle_id: note.id)

      delete "/api/notes/#{note.slug}/tentacle", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"stopped" => true})
    end
  end
end
