require "rails_helper"

RSpec.describe Tentacles::SessionControl do
  let(:note) { create(:note, :with_head_revision, title: "Target Agent") }

  before do
    Tentacles::Authorization.instance_variable_set(:@enabled, nil) if Tentacles::Authorization.instance_variable_defined?(:@enabled)
    allow(Tentacles::Authorization).to receive(:enabled?).and_return(true)
    TentacleRuntime::SESSIONS.clear
  end

  after { TentacleRuntime::SESSIONS.clear }

  describe ".activate" do
    it "spawns a fresh session when none exists" do
      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9991, started_at: Time.current,
        cwd: "/tmp/worktree-#{note.id}", repo_root_fingerprint: "fp:1",
        pre_persistence_fingerprint?: false,
        initial_prompt_delivered?: false
      )
      allow(WorktreeService).to receive(:ensure).and_return("/tmp/worktree-#{note.id}")
      expect(TentacleRuntime).to receive(:start).with(hash_including(note_slug: note.slug)).and_return(fake)

      result = described_class.activate(note: note, command: ["claude"])

      expect(result.reused).to be false
      expect(result.session).to eq(fake)
      expect(result.routed_prompt_delivered).to be false
    end

    it "reports routed_prompt_delivered: true on fresh session when the runtime confirms delivery" do
      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9991, started_at: Time.current,
        cwd: "/tmp/worktree-#{note.id}", repo_root_fingerprint: "fp:1",
        pre_persistence_fingerprint?: false,
        initial_prompt_delivered?: true
      )
      allow(WorktreeService).to receive(:ensure).and_return("/tmp/worktree-#{note.id}")
      expect(TentacleRuntime).to receive(:start)
        .with(hash_including(initial_prompt: "wake up", note_slug: note.slug))
        .and_return(fake)

      result = described_class.activate(note: note, command: ["claude"], initial_prompt: "wake up")

      expect(result.routed_prompt_delivered).to be true
    end

    it "reports routed_prompt_delivered: false on fresh session when the runtime could not confirm delivery" do
      fake = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 9991, started_at: Time.current,
        cwd: "/tmp/worktree-#{note.id}", repo_root_fingerprint: "fp:1",
        pre_persistence_fingerprint?: false,
        initial_prompt_delivered?: false
      )
      allow(WorktreeService).to receive(:ensure).and_return("/tmp/worktree-#{note.id}")
      expect(TentacleRuntime).to receive(:start).and_return(fake)

      result = described_class.activate(note: note, command: ["claude"], initial_prompt: "wake up")

      expect(result.routed_prompt_delivered).to be false
    end

    it "reuses a live session whose cwd + repo identity still match" do
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(WorktreeService).not_to receive(:ensure)
      expect(TentacleRuntime).not_to receive(:start)

      result = described_class.activate(note: note, command: ["claude"])
      expect(result.reused).to be true
      expect(result.session).to eq(existing)
    end

    it "delivers routed_prompt to the PTY on reuse" do
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      fresh_fp = Tentacles::BootConfig.repo_root_fingerprint(Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: fresh_fp,
        pre_persistence_fingerprint?: false,
        submit_sequence: "\e[13u"
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(TentacleRuntime).to receive(:write).with(tentacle_id: note.id, data: "hello\e[13u")

      result = described_class.activate(note: note, command: ["claude"], initial_prompt: "hello")
      expect(result.routed_prompt_delivered).to be true
    end

    it "raises StaleSession when live cwd diverges from the note's current boot config" do
      stale_cwd = "/tmp/stale-#{SecureRandom.hex(4)}"
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: stale_cwd, repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect {
        described_class.activate(note: note, command: ["claude"])
      }.to raise_error(Tentacles::SessionControl::StaleSession) { |err|
        expect(err.reason).to eq("cwd_changed")
        expect(err.current_cwd).to eq(stale_cwd)
      }
    end

    it "raises StaleSession when repo identity fingerprint mismatches" do
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      stale_fp = "#{File.realpath(Rails.root)}:777777"
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: stale_fp,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect {
        described_class.activate(note: note, command: ["claude"])
      }.to raise_error(Tentacles::SessionControl::StaleSession) { |err|
        expect(err.reason).to eq("repo_identity_changed")
      }
    end

    it "raises StaleSession reason fingerprint_unrecoverable when a post-fix reattached session lost its fingerprint" do
      # Reattached sessions whose fingerprint key WAS persisted but
      # came back nil cannot be identity-verified — fail closed
      # instead of routing input to a possibly-stale repo identity.
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: false
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect {
        described_class.activate(note: note, command: ["claude"])
      }.to raise_error(Tentacles::SessionControl::StaleSession) { |err|
        expect(err.reason).to eq("fingerprint_unrecoverable")
      }
    end

    it "allows reuse of a legacy reattached session (predates fingerprint persistence) and logs a warning" do
      # Pre-fix records were written before persist_tentacle_session_record!
      # started always-recording the fingerprint key. Failing them closed
      # would strand every alive tentacle on deploy. Allow the reuse on a
      # one-time, log-loud basis — the next stop rotates the record.
      existing_cwd = WorktreeService.path_for(tentacle_id: note.id, repo_root: Rails.root)
      existing = instance_double(
        TentacleRuntime::Session,
        alive?: true, pid: 1, started_at: Time.current,
        cwd: existing_cwd, repo_root_fingerprint: nil,
        pre_persistence_fingerprint?: true
      )
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(Rails.logger).to receive(:warn).with(/legacy session.*without fingerprint verification/)

      result = described_class.activate(note: note, command: ["claude"])
      expect(result.reused).to be(true)
      expect(result.session).to eq(existing)
    end

    it "raises InvalidBootConfig when tentacle_workspace cannot resolve" do
      PropertyDefinition.find_or_create_by!(key: "tentacle_workspace") do |d|
        d.value_type = "text"
        d.system = true
      end
      Properties::SetService.call(note: note, changes: {"tentacle_workspace" => "missing-workspace"})

      expect {
        described_class.activate(note: note.reload, command: ["claude"])
      }.to raise_error(Tentacles::SessionControl::InvalidBootConfig, /tentacle_workspace/)
    end

    it "raises InvalidBootConfig when initial_prompt exceeds 2KB" do
      expect {
        described_class.activate(note: note, command: ["claude"], initial_prompt: "x" * 3000)
      }.to raise_error(Tentacles::SessionControl::InvalidBootConfig, /initial_prompt/)
    end

    describe "tentacle_yolo opt-in" do
      let(:fake_session) do
        instance_double(
          TentacleRuntime::Session,
          alive?: true, pid: 9991, started_at: Time.current,
          cwd: "/tmp/worktree-#{note.id}", repo_root_fingerprint: "fp:1",
          pre_persistence_fingerprint?: false,
          initial_prompt_delivered?: false
        )
      end

      before do
        PropertyDefinition.find_or_create_by!(key: "tentacle_yolo") do |d|
          d.value_type = "boolean"
          d.system = true
        end
        allow(WorktreeService).to receive(:ensure).and_return("/tmp/worktree-#{note.id}")
        allow(TentacleRuntime).to receive(:start).and_return(fake_session)
      end

      it "writes yolo settings into the worktree when the charter has tentacle_yolo=true" do
        Properties::SetService.call(note: note, changes: {"tentacle_yolo" => true})
        expect(WorktreeService).to receive(:write_yolo_settings!).with(path: "/tmp/worktree-#{note.id}")

        described_class.activate(note: note.reload, command: ["claude"])
      end

      it "does not write yolo settings when tentacle_yolo is unset" do
        expect(WorktreeService).not_to receive(:write_yolo_settings!)
        described_class.activate(note: note, command: ["claude"])
      end

      it "does not write yolo settings when tentacle_yolo is false" do
        Properties::SetService.call(note: note, changes: {"tentacle_yolo" => false})
        expect(WorktreeService).not_to receive(:write_yolo_settings!)
        described_class.activate(note: note.reload, command: ["claude"])
      end
    end
  end
end
