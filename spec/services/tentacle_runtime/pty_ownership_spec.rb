require "rails_helper"
require "socket"

# :dtach_integration switches DatabaseCleaner to :truncation. These
# examples spawn real PTY children whose reader threads write to
# TentacleSession on separate DB connections — the default :transaction
# strategy would hide those writes from the test thread.
RSpec.describe TentacleRuntime, "PTY-mode cross-process ownership", :dtach_integration do
  let(:note) { create(:note, title: "Owned Agent") }
  # A pid above any plausible pid_max — Process.kill(0, ...) reliably
  # raises ESRCH, so the reaper treats it as dead.
  let(:dead_pid) { 2_147_483_646 }

  before do
    allow(TentacleChannel).to receive(:broadcast_output)
    allow(TentacleChannel).to receive(:broadcast_exit)
  end

  after { described_class.reset! }

  def foreign_record(host:, pid:)
    TentacleSession.create!(
      tentacle_note_id: note.id, status: "alive", command: "sleep 5",
      started_at: Time.current, pid: pid, host: host, dtach_socket: nil
    )
  end

  describe ".start (PTY mode)" do
    it "persists an alive TentacleSession record for this host" do
      session = described_class.start(tentacle_id: note.id, command: ["sleep", "5"])

      record = TentacleSession.alive.find_by(tentacle_note_id: note.id)
      expect(record).to be_present
      expect(record.host).to eq(Socket.gethostname)
      expect(record.dtach_socket).to be_nil
      expect(record.pid).to eq(session.pid)
    end

    it "finalizes the record when the session stops" do
      described_class.start(tentacle_id: note.id, command: ["sleep", "5"])
      described_class.stop(tentacle_id: note.id)

      expect(TentacleSession.alive.where(tentacle_note_id: note.id)).to be_empty
    end

    it "refuses to spawn a duplicate when another process already owns an alive session" do
      # Another web process owns a live session: an alive record exists,
      # but this process's in-memory SESSIONS map is empty. The per-note
      # alive unique index makes the duplicate persist fail atomically.
      foreign_record(host: "other-web-host", pid: dead_pid)

      expect {
        described_class.start(tentacle_id: note.id, command: ["sleep", "5"])
      }.to raise_error(TentacleRuntime::ForeignOwnedSession)

      expect(described_class.get(note.id)).to be_nil
      expect(TentacleSession.alive.where(tentacle_note_id: note.id).count).to eq(1)
    end
  end

  describe ".bootstrap_sessions! PTY reaping" do
    it "finalizes an alive PTY record for this host whose pid is dead" do
      foreign_record(host: Socket.gethostname, pid: dead_pid)

      described_class.bootstrap_sessions!

      record = TentacleSession.find_by(tentacle_note_id: note.id)
      expect(record.status).to eq("exited")
      expect(record.exit_reason).to eq("missing_pid")
    end

    it "leaves a PTY record owned by a different host untouched" do
      foreign_record(host: "other-host", pid: dead_pid)

      described_class.bootstrap_sessions!

      expect(TentacleSession.find_by(tentacle_note_id: note.id).status).to eq("alive")
    end

    it "reaps a same-host PTY record at bootstrap regardless of pid liveness (PID-reuse hardening)" do
      # Bootstrap only runs at process boot, and at that point SESSIONS
      # is empty — any same-host alive record predates this worker. Even
      # if its pid happens to be live, that pid was reused by an
      # unrelated process and the old PTY child is gone. Trusting bare
      # PID liveness would wedge the per-note unique index forever
      # (Codex finding: PID-reuse can preserve a stale alive row).
      foreign_record(host: Socket.gethostname, pid: Process.pid)

      described_class.bootstrap_sessions!

      record = TentacleSession.find_by(tentacle_note_id: note.id)
      expect(record.status).to eq("exited")
      expect(record.exit_reason).to eq("missing_pid")
    end

    it "reaps a cross-host PTY record whose fencing lease has expired" do
      record = foreign_record(host: "ghost-host", pid: dead_pid)
      original_token = SecureRandom.uuid
      # Lease genuinely expired — owner has not renewed in LEASE_DURATION.
      # Unambiguous death signal, unlike a stale timestamp comparison.
      record.update_columns(lease_token: original_token, lease_expires_at: 1.minute.ago)

      described_class.bootstrap_sessions!

      record.reload
      expect(record.status).to eq("exited")
      expect(record.exit_reason).to eq("missing_pid")
      # Token rotated so a re-awakened stale owner cannot CAS-renew its
      # way back to alive (Codex finding: fencing semantics).
      expect(record.lease_token).not_to eq(original_token)
    end

    it "leaves a cross-host PTY record with a valid lease untouched" do
      record = foreign_record(host: "ghost-host", pid: dead_pid)
      record.update_columns(
        lease_token: SecureRandom.uuid,
        lease_expires_at: 30.minutes.from_now
      )

      described_class.bootstrap_sessions!

      expect(record.reload.status).to eq("alive")
    end

    it "leaves a cross-host PTY record without a lease untouched (legacy / operator review)" do
      foreign_record(host: "ghost-host", pid: dead_pid)
      # No lease columns set — pre-fencing record. We refuse to fence
      # foreign records without explicit lease metadata.
      described_class.bootstrap_sessions!

      expect(TentacleSession.find_by(tentacle_note_id: note.id).status).to eq("alive")
    end
  end

  describe "lease renewal self-fencing" do
    it "self-fences the local session when renew_lease! finds the lease was reclaimed" do
      session = described_class.start(tentacle_id: note.id, command: ["sleep", "10"])
      # Simulate a foreign reaper rotating the lease token. From this
      # session's perspective the row no longer carries its claim.
      TentacleSession.where(tentacle_note_id: note.id).update_all(lease_token: SecureRandom.uuid)

      stop_called = Concurrent::AtomicBoolean.new
      allow(described_class).to receive(:stop) { stop_called.make_true; nil }

      expect(session.send(:renew_lease!)).to eq(:fenced)
      # Self-fence dispatches stop in a detached thread; allow it to run.
      20.times { break if stop_called.true?; sleep 0.02 }
      expect(stop_called.true?).to be(true)
    end

    it "returns :renewed and pushes lease_expires_at forward on a normal heartbeat tick" do
      session = described_class.start(tentacle_id: note.id, command: ["sleep", "10"])
      record_before = TentacleSession.find_by(tentacle_note_id: note.id)
      old_expiry = record_before.lease_expires_at

      sleep 0.01
      expect(session.send(:renew_lease!)).to eq(:renewed)

      expect(TentacleSession.find_by(tentacle_note_id: note.id).lease_expires_at).to be > old_expiry
    end
  end

  describe ".get_or_reattach" do
    it "returns the in-memory session on a local SESSIONS hit without a DB lookup" do
      # stop: nil so the reset! teardown hook can tear the double down.
      session = instance_double(TentacleRuntime::Session, stop: nil)
      TentacleRuntime::SESSIONS[note.id] = session
      expect(TentacleSession).not_to receive(:find_by)

      expect(described_class.get_or_reattach(note.id)).to eq(session)
    end

    it "returns nil when dtach is disabled, even if an alive record exists" do
      foreign_record(host: "other-web-host", pid: dead_pid)
      # dtach is off by default in the test env — a record spawned by
      # another process is genuinely unreachable from here.
      expect(described_class.get_or_reattach(note.id)).to be_nil
    end

    it "returns nil for a PTY-mode record (no socket — unreachable cross-process)" do
      allow(described_class).to receive(:dtach_enabled?).and_return(true)
      foreign_record(host: "other-web-host", pid: dead_pid)

      expect(described_class.get_or_reattach(note.id)).to be_nil
    end

    it "returns nil when dtach is enabled but no alive record exists" do
      allow(described_class).to receive(:dtach_enabled?).and_return(true)

      expect(described_class.get_or_reattach(note.id)).to be_nil
    end

    it "returns nil when a dtach record exists but its socket is gone from disk" do
      allow(described_class).to receive(:dtach_enabled?).and_return(true)
      TentacleSession.create!(
        tentacle_note_id: note.id, status: "alive", command: "sleep 5",
        started_at: Time.current, pid: dead_pid, host: "other-web-host",
        dtach_socket: "/run/nm-tentacles/gone-#{SecureRandom.hex(4)}.sock"
      )

      # reattach_record bails when the socket file is missing — nothing
      # to attach to, so no duplicate session is conjured.
      expect(described_class.get_or_reattach(note.id)).to be_nil
    end
  end
end
