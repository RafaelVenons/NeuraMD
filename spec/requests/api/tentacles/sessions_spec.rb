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
        # Operator layout /home/venom/... does not exist on CI; use a path
        # under the test-suite's allowed prefix (rails_helper) so
        # BootConfig.canonicalize_cwd resolves successfully.
        cwd = File.join(Tentacles::BootConfig.allowed_cwd_prefixes.first, "maple-#{SecureRandom.hex(4)}")
        FileUtils.mkdir_p(cwd)
        note = make_note("Booted")
        Properties::SetService.call(
          note: note,
          changes: {
            "tentacle_cwd" => cwd,
            "tentacle_initial_prompt" => "Você é Dev Maple. Leia o charter."
          }
        )

        fake = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 9001, started_at: Time.utc(2026, 4, 20, 14)
        )
        expect(WorktreeService).to receive(:ensure).with(
          hash_including(tentacle_id: note.id, repo_root: cwd)
        ).and_return("#{cwd}/tmp/tentacles/#{note.id}")
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
      ensure
        FileUtils.remove_entry(cwd) if cwd && File.directory?(cwd)
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
        # See note on /home/venom on the paired test above.
        cwd = File.join(Tentacles::BootConfig.allowed_cwd_prefixes.first, "cwd-only-#{SecureRandom.hex(4)}")
        FileUtils.mkdir_p(cwd)
        note = make_note("CwdOnly")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => cwd}
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
      ensure
        FileUtils.remove_entry(cwd) if cwd && File.directory?(cwd)
      end

      it "returns 422 when stored tentacle_cwd is outside the whitelist" do
        sign_in user
        note = make_note("TaintedCwd")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => "/etc"}
        )

        expect(WorktreeService).not_to receive(:ensure)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "bash"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to include("tentacle_cwd")
      end

      it "returns 422 when stored tentacle_cwd does not exist" do
        sign_in user
        note = make_note("VanishedCwd")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_cwd" => "/home/venom/projects/does-not-exist-#{SecureRandom.hex(4)}"}
        )

        expect(WorktreeService).not_to receive(:ensure)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "bash"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to include("tentacle_cwd")
      end

      it "signals reused=true and skips TentacleRuntime.start when a live session already exists" do
        sign_in user
        note = make_note("LiveReuse")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_initial_prompt" => "fresh boot message"}
        )

        existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
        fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
        existing = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 4242, started_at: Time.utc(2026, 4, 20, 10),
          cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
          pre_persistence_fingerprint?: false
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

      it "returns 409 when the live session's cwd no longer matches the note's boot config" do
        sign_in user
        note = make_note("StaleReuse")

        # Simulate a session that was spawned for an earlier boot config
        # (attached to a different worktree path). Any mutation to the
        # note's tentacle_workspace/tentacle_cwd after this point would
        # produce the same effect; here we just construct the divergence
        # directly by giving the live session a path the current resolver
        # cannot produce.
        stale_cwd = "/tmp/stale-worktree-#{SecureRandom.hex(4)}"
        existing = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 9999, started_at: Time.current,
          cwd: stale_cwd, repo_root_fingerprint: nil,
          pre_persistence_fingerprint?: false
        )
        TentacleRuntime::SESSIONS[note.id] = existing

        expect(TentacleRuntime).not_to receive(:write)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:conflict)
        body = response.parsed_body
        expect(body["stale_boot_config"]).to eq(true)
        expect(body["stale_reason"]).to eq("cwd_changed")
        expect(body["current_cwd"]).to eq(stale_cwd)
        expect(body["desired_cwd"]).to include("tmp/tentacles/#{note.id}")
      end

      it "returns 409 when the repo identity changed under the same worktree path" do
        sign_in user
        note = make_note("ReplacedRepo")

        # Live session carries a fingerprint from an old repo identity
        # (simulates: workspace dir rm -rf + re-clone at same path). The
        # current fingerprint resolves to Rails.root with its real inode;
        # the fingerprint stored on the session points at a different inode
        # even though the cwd path would still match.
        existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
        stale_fp = "#{File.realpath(Rails.root)}:999999999"
        existing = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 1234, started_at: Time.current,
          cwd: existing_cwd, repo_root_fingerprint: stale_fp,
          pre_persistence_fingerprint?: false
        )
        TentacleRuntime::SESSIONS[note.id] = existing

        expect(TentacleRuntime).not_to receive(:write)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:conflict)
        body = response.parsed_body
        expect(body["stale_boot_config"]).to eq(true)
        expect(body["stale_reason"]).to eq("repo_identity_changed")
      end

      it "returns 409 with dirty_worktree: true when the worktree refresh refuses uncommitted changes" do
        sign_in user
        note = make_note("DirtyWorktree")

        # Simulate WorktreeService.ensure raising the fail-closed signal:
        # tracked files are modified inside the transversal worktree, so
        # the refresh cannot proceed without destroying agent work.
        allow(WorktreeService).to receive(:ensure).and_raise(
          WorktreeService::DirtyWorktreeError, "refusing to refresh: WIP detected"
        )
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:conflict)
        body = response.parsed_body
        expect(body["dirty_worktree"]).to eq(true)
        expect(body["error"]).to match(/uncommitted local changes/i)
        expect(body["error"]).to match(/commit, stash, or push/i)
        expect(body["detail"]).to include("WIP detected")
      end

      it "passes the routed initial_prompt to TentacleRuntime.start when starting fresh" do
        sign_in user
        note = make_note("Routed")

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current, initial_prompt_delivered?: true)
        allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:initial_prompt]).to eq("Implement OAuth Discord.")
          expect(kwargs[:note_slug]).to eq(note.slug)
          fake
        end

        post "/api/notes/#{note.slug}/tentacle",
          params: {command: "claude", initial_prompt: "Implement OAuth Discord."}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["routed_prompt_delivered"]).to eq(true)
      end

      it "merges boot config prompt with routed initial_prompt on fresh start" do
        sign_in user
        note = make_note("Merged")
        Properties::SetService.call(
          note: note,
          changes: {"tentacle_initial_prompt" => "You are the Especialista."}
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current, initial_prompt_delivered?: true)
        allow(WorktreeService).to receive(:ensure).and_return("/stub/worktree")
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:initial_prompt]).to eq("You are the Especialista.\n\nImplement OAuth Discord.")
          fake
        end

        post "/api/notes/#{note.reload.slug}/tentacle",
          params: {command: "claude", initial_prompt: "Implement OAuth Discord."}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "writes routed initial_prompt to the PTY when reusing an alive session" do
        sign_in user
        note = make_note("AliveRoute")
        existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
        fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
        existing = instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 5555, started_at: Time.utc(2026, 4, 20, 11),
          cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
          pre_persistence_fingerprint?: false
        )
        allow(existing).to receive(:instance_variable_get).with(:@command).and_return(%w[claude])
        TentacleRuntime::SESSIONS[note.id] = existing

        expect(TentacleRuntime).to receive(:write).with(tentacle_id: note.id, data: "Implement OAuth Discord.\n")
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.slug}/tentacle",
          params: {command: "claude", initial_prompt: "Implement OAuth Discord."}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["reused"]).to eq(true)
        expect(body["routed_prompt_delivered"]).to eq(true)
      end

      it "returns 422 when routed initial_prompt exceeds 2KB" do
        sign_in user
        note = make_note("Oversize")

        expect(TentacleRuntime).not_to receive(:start)
        expect(TentacleRuntime).not_to receive(:write)

        post "/api/notes/#{note.slug}/tentacle",
          params: {command: "claude", initial_prompt: "x" * 2049}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to include("initial_prompt")
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

    context "when the note points at a shared workspace" do
      let(:workspace_root) { Dir.mktmpdir("neuramd-sessions-ws-") }
      let(:workspace_path) { File.join(workspace_root, "neuramd") }

      around do |example|
        original = ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"]
        ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"] = workspace_root
        FileUtils.mkdir_p(workspace_path)
        out, status = Open3.capture2e(
          {"GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"},
          "git", "init", "--quiet", "--initial-branch=main", chdir: workspace_path
        )
        raise "git init failed: #{out}" unless status.success?
        example.run
      ensure
        ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"] = original
        FileUtils.remove_entry(workspace_root) if File.directory?(workspace_root)
      end

      before do
        PropertyDefinition.find_or_create_by!(key: "tentacle_workspace") do |d|
          d.value_type = "text"
          d.system = true
        end
        PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
          d.value_type = "text"
          d.system = true
        end
      end

      it "routes WorktreeService through the resolved workspace with link_shared: false" do
        sign_in user
        note = make_note("InWorkspace")
        Properties::SetService.call(note: note, changes: {"tentacle_workspace" => "neuramd"})

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(WorktreeService).to receive(:ensure) do |**kwargs|
          expect(kwargs[:tentacle_id]).to eq(note.id)
          expect(kwargs[:repo_root]).to eq(workspace_path)
          expect(kwargs[:worktree_root]).to eq(File.join(workspace_root, ".tentacle-worktrees", "neuramd"))
          expect(kwargs[:link_shared]).to eq(false)
          "/stub/workspace-worktree"
        end
        expect(TentacleRuntime).to receive(:start) do |**kwargs|
          expect(kwargs[:cwd]).to eq("/stub/workspace-worktree")
          fake
        end

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "prefers tentacle_workspace over tentacle_cwd when both are set" do
        sign_in user
        note = make_note("PreferWs")
        Properties::SetService.call(
          note: note,
          changes: {
            "tentacle_workspace" => "neuramd",
            "tentacle_cwd" => "/home/venom/projects/NeuraMD"
          }
        )

        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(WorktreeService).to receive(:ensure) do |**kwargs|
          expect(kwargs[:repo_root]).to eq(workspace_path)
          expect(kwargs[:worktree_root]).to include(".tentacle-worktrees/neuramd")
          "/stub/worktree"
        end
        allow(TentacleRuntime).to receive(:start).and_return(fake)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:created)
      end

      it "returns 422 and does not spawn when tentacle_workspace cannot be resolved" do
        sign_in user
        note = make_note("BadWs")
        Properties::SetService.call(note: note, changes: {"tentacle_workspace" => "missing-one"})

        expect(WorktreeService).not_to receive(:ensure)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to include("tentacle_workspace", "missing-one")
      end

      it "returns 422 even when both tentacle_workspace and tentacle_cwd are set but workspace is invalid" do
        sign_in user
        note = make_note("BadWsStaleCwd")
        Properties::SetService.call(
          note: note,
          changes: {
            "tentacle_workspace" => "missing-renamed",
            "tentacle_cwd" => "/etc"
          }
        )

        expect(WorktreeService).not_to receive(:ensure)
        expect(TentacleRuntime).not_to receive(:start)

        post "/api/notes/#{note.reload.slug}/tentacle", params: {command: "claude"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json"}

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to include("tentacle_workspace")
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
