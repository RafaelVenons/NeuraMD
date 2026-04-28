require "rails_helper"

RSpec.describe "API S2S tentacle sessions", type: :request do
  let(:token) { "test-token-#{SecureRandom.hex(16)}" }
  let(:headers) do
    {
      "CONTENT_TYPE" => "application/json",
      "X-NeuraMD-Agent-Token" => token
    }
  end

  def make_agent_note(title = "Agent Under Test", tags: %w[agente-team agente-under-test])
    note = create(:note, title: title)
    rev = create(:note_revision, note: note, content_markdown: "body")
    note.update_columns(head_revision_id: rev.id)
    tags.each do |tag_name|
      tag = Tag.find_or_create_by!(name: tag_name) { |t| t.tag_scope = "note" }
      note.tags << tag unless note.tags.include?(tag)
    end
    note
  end

  before do
    TentacleRuntime::SESSIONS.clear
    allow(Tentacles::Authorization).to receive(:enabled?).and_return(true)
    credentials = Rails.application.credentials
    allow(credentials).to receive(:agent_s2s_token).and_return(token)
  end

  after { TentacleRuntime::SESSIONS.clear }

  describe "POST /api/s2s/tentacles/:slug/activate" do
    it "returns 401 when the token header is missing" do
      note = make_agent_note
      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("X-NeuraMD-Agent-Token")
    end

    it "returns 401 when the token does not match credentials" do
      note = make_agent_note
      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json,
        headers: headers.merge("X-NeuraMD-Agent-Token" => "wrong-value")

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 503 when agent_s2s_token is not configured" do
      credentials = Rails.application.credentials
      allow(credentials).to receive(:agent_s2s_token).and_return(nil)
      note = make_agent_note

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to include("S2S token not configured")
    end

    it "returns 403 when Tentacles feature is disabled" do
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
      note = make_agent_note

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when the target note does not exist" do
      post "/api/s2s/tentacles/no-such-slug/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 403 when the target note carries no agent tag" do
      note = make_agent_note("Plain Note", tags: %w[plain misc])

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("agent tag")
    end

    it "creates a fresh session (201) and passes command through" do
      note = make_agent_note
      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1234, started_at: Time.current,
        cwd: WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root),
        repo_root_fingerprint: Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      )
      allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
      expect(TentacleRuntime).to receive(:start) do |**kwargs|
        expect(kwargs[:command]).to eq(["claude"])
        expect(kwargs[:persistence]).to eq({kind: "s2s"})
        fake
      end

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {command: "claude"}.to_json, headers: headers

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["activated"]).to eq(true)
      expect(body["reused"]).to eq(false)
      expect(body["pid"]).to eq(1234)
      expect(body["command"]).to eq(["claude"])
    end

    it "accepts the s2s persistence descriptor without ArgumentError on cold start" do
      # Regression: previously unknown to Persistence::KINDS, which
      # raised from TentacleRuntime.start BEFORE the controller could
      # stub it out. Here we let the real validator run and pass a
      # mock Session via TentacleRuntime stubbed after validation.
      note = make_agent_note
      allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")

      expect {
        TentacleRuntime::Persistence.validate!({kind: "s2s"})
      }.not_to raise_error

      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root),
        repo_root_fingerprint: Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      )
      allow(TentacleRuntime).to receive(:start).and_call_original
      # Intercept the actual PTY spawn by stubbing start internals.
      allow(TentacleRuntime).to receive(:start).and_return(fake)

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {command: "claude"}.to_json, headers: headers

      expect(response).to have_http_status(:created)
    end

    it "returns 200 reused=true when a live session already matches the boot config" do
      note = make_agent_note
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(TentacleRuntime).not_to receive(:start)

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {command: "claude"}.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["reused"]).to eq(true)
    end

    it "writes routed initial_prompt when reusing an alive session" do
      note = make_agent_note
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
        pre_persistence_fingerprint?: false,
        submit_sequence: "\e[13u"
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(TentacleRuntime).to receive(:write).with(tentacle_id: note.id, data: "wake up\e[13u")

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {command: "claude", initial_prompt: "wake up"}.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["routed_prompt_delivered"]).to eq(true)
    end

    it "returns 409 when the live session cwd is stale" do
      note = make_agent_note
      stale_cwd = "/tmp/stale-#{SecureRandom.hex(4)}"
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9, started_at: Time.current,
        cwd: stale_cwd, repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["stale_boot_config"]).to eq(true)
      expect(response.parsed_body["stale_reason"]).to eq("cwd_changed")
    end

    it "returns 409 with dirty_worktree: true when the worktree refresh refuses uncommitted changes" do
      note = make_agent_note
      allow(WorktreeService).to receive(:ensure).and_raise(
        WorktreeService::DirtyWorktreeError, "refusing to refresh: WIP detected"
      )
      expect(TentacleRuntime).not_to receive(:start)

      post "/api/s2s/tentacles/#{note.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
      body = response.parsed_body
      expect(body["dirty_worktree"]).to eq(true)
      expect(body["error"]).to match(/uncommitted local changes/i)
      expect(body["detail"]).to include("WIP detected")
    end

    it "returns 422 when the note's tentacle_workspace does not resolve" do
      PropertyDefinition.find_or_create_by!(key: "tentacle_workspace") do |d|
        d.value_type = "text"
        d.system = true
      end
      note = make_agent_note
      Properties::SetService.call(note: note, changes: {"tentacle_workspace" => "nope"})

      post "/api/s2s/tentacles/#{note.reload.slug}/activate",
        params: {}.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("tentacle_workspace")
    end
  end

  describe "DELETE /api/s2s/tentacles/:slug" do
    it "returns 401 when the token header is missing" do
      note = make_agent_note
      delete "/api/s2s/tentacles/#{note.slug}",
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "stops the session and returns rich response (stopped + terminated + pid + escalated_to_kill + ended_at)" do
      note = make_agent_note
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 4242, started_at: Time.current,
        cwd: "/tmp/wt-#{note.id}", repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false,
        force_killed?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing
      expect(TentacleRuntime).to receive(:stop).with(hash_including(tentacle_id: note.id)) do
        TentacleRuntime::SESSIONS.delete(note.id)
      end

      delete "/api/s2s/tentacles/#{note.slug}", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["stopped"]).to eq(true) # back-compat field preserved
      expect(body["terminated"]).to eq(true)
      expect(body["slug"]).to eq(note.slug)
      expect(body["tentacle_id"]).to eq(note.id)
      expect(body["pid"]).to eq(4242)
      expect(body["escalated_to_kill"]).to eq(false)
      expect(body["ended_at"]).to be_a(String)
    end

    it "is idempotent on no-session: returns 200 with terminated: false and reason: no_session" do
      note = make_agent_note
      # SESSIONS map is empty for this note id
      expect(TentacleRuntime).not_to receive(:stop)

      delete "/api/s2s/tentacles/#{note.slug}", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["stopped"]).to eq(true) # back-compat
      expect(body["terminated"]).to eq(false)
      expect(body["reason"]).to eq("no_session")
      expect(body["slug"]).to eq(note.slug)
    end

    it "honors force: true by passing grace: 0 through to TentacleRuntime.stop" do
      note = make_agent_note
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 7, started_at: Time.current,
        cwd: "/tmp/wt-#{note.id}", repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false,
        force_killed?: true
      )
      TentacleRuntime::SESSIONS[note.id] = existing
      expect(TentacleRuntime).to receive(:stop).with(tentacle_id: note.id, grace: 0) do
        TentacleRuntime::SESSIONS.delete(note.id)
      end

      delete "/api/s2s/tentacles/#{note.slug}",
        params: {force: true}.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["terminated"]).to eq(true)
      expect(body["escalated_to_kill"]).to eq(true)
    end

    it "refuses non-agent notes (tag gate still applies)" do
      note = make_agent_note("Plain", tags: %w[plain])

      delete "/api/s2s/tentacles/#{note.slug}", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "recovers a stale session: DELETE then POST /activate succeeds" do
      note = make_agent_note
      stale_cwd = "/tmp/stale-#{SecureRandom.hex(4)}"
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9, started_at: Time.current,
        cwd: stale_cwd, repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      post "/api/s2s/tentacles/#{note.slug}/activate", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:conflict)

      allow(TentacleRuntime).to receive(:stop).with(tentacle_id: note.id) do
        TentacleRuntime::SESSIONS.delete(note.id)
      end
      delete "/api/s2s/tentacles/#{note.slug}", headers: headers
      expect(response).to have_http_status(:ok)

      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 77, started_at: Time.current,
        cwd: WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root),
        repo_root_fingerprint: Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      )
      allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
      allow(TentacleRuntime).to receive(:start).and_return(fake)

      post "/api/s2s/tentacles/#{note.slug}/activate", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:created)
    end
  end
end
