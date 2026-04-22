require "rails_helper"
require "tmpdir"

# End-to-end smoke test for the dtach-backed tentacle runtime.
#
# Exercises the full production contract "deploy do web não mata
# tentáculos": spawn a real dtach-detached child, simulate Puma shutdown
# (detach without killing), then bootstrap_sessions! on a fresh boot.
# Each piece has unit coverage elsewhere, but the chain itself — including
# the reader-thread teardown inside `Session#detach_without_killing` and
# reattach round-trip I/O — only surfaces with a real dtach binary.
#
# Tagged :dtach_integration so CI (which installs dtach) runs these and
# dev machines without the binary auto-skip via the rails_helper hook.
# DatabaseCleaner uses :truncation so the reader thread's AR writes are
# visible from the main thread.
RSpec.describe TentacleRuntime, "dtach chain", :dtach_integration do
  let(:note) { create(:note, title: "dtach-smoke-#{SecureRandom.hex(4)}") }
  let(:tentacle_id) { note.id }

  around do |example|
    Dir.mktmpdir("nm-tentacles-chain-") do |dir|
      @runtime_dir = dir
      with_dtach_env(dir) { example.run }
    ensure
      cleanup_leftover_children(dir)
    end
  end

  before do
    # `ActionCable::Server::Worker` has a lazy-load race against
    # ActiveRecordConnectionManagement when broadcast_to is triggered
    # from a background thread in :test env. Production eager-loads the
    # cable server at boot, so this only affects specs. Stubbing matches
    # the existing pattern in tentacle_runtime/context_warning_spec.rb.
    # The stubs do NOT hide the broadcast contract — assertions below
    # verify the expected payloads are forwarded after reattach.
    allow(TentacleChannel).to receive(:broadcast_output)
    allow(TentacleChannel).to receive(:broadcast_exit)
    allow(TentacleChannel).to receive(:broadcast_context_warning)
  end

  after do
    TentacleRuntime.reset!
  end

  describe "shutdown without kill, reattach on boot" do
    it "keeps the detached child alive, preserves the session record, and reattaches across a simulated restart" do
      spawned = TentacleRuntime.start(tentacle_id: tentacle_id, command: ["cat"])
      child_pid = spawned.pid
      expect(child_pid).to be_a(Integer)
      expect(spawned.alive?).to be true
      expect(spawned.dtach_mode?).to be true

      record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
      expect(record).to be_present
      expect(record.pid).to eq(child_pid)
      expect(record.dtach_socket).to start_with(@runtime_dir)

      TentacleRuntime.shutdown!(grace: 2)
      expect(TentacleRuntime.get(tentacle_id)).to be_nil

      # Let the reader thread unwind through its ensure block after
      # close_streams. The detach path must not flip the record to exited.
      sleep 0.3

      expect(process_alive?(child_pid)).to be(true),
        "detached child #{child_pid} should survive Puma shutdown"
      expect(record.reload.status).to eq("alive"),
        "record should stay alive after detach; was #{record.status.inspect}"
      expect(record.ended_at).to be_nil

      TentacleRuntime.bootstrap_sessions!

      # Anchor the reattach assertions to THIS note's record — other
      # specs (or leftover prod state on CI) may have unrelated alive
      # sessions, so a bare count would be meaningless.
      alive_for_note = TentacleSession.alive.where(tentacle_note_id: tentacle_id).to_a
      expect(alive_for_note.size).to eq(1),
        "expected exactly one alive record for tentacle_note_id=#{tentacle_id}, got #{alive_for_note.size}"
      expect(alive_for_note.first.pid).to eq(child_pid)

      reattached = TentacleRuntime.get(tentacle_id)
      expect(reattached).to be_present
      expect(reattached.alive?).to be true
      expect(reattached.pid).to eq(child_pid)
      expect(reattached.dtach_mode?).to be true

      # dtach -a attach proxy takes a moment to finish handshaking. Retry
      # the write until the echo lands so the spec reflects the real
      # contract ("eventually consistent after reattach") without flaking
      # on test-env scheduling jitter.
      deadline = Time.current + 5
      until reattached.transcript.include?("hello-reattach") || Time.current > deadline
        reattached.write("hello-reattach\n")
        sleep 0.1
      end
      expect(reattached.transcript).to include("hello-reattach"),
        "new attach proxy should forward writes and receive echo from cat"

      # Broadcast contract: the stub above is necessary (ActionCable
      # lazy-load race in :test), but it must not hide a broken pipeline.
      # After reattach, the reader thread MUST forward the cat echo to
      # subscribers via broadcast_output for THIS tentacle_id.
      expect(TentacleChannel).to have_received(:broadcast_output).with(
        hash_including(
          tentacle_id: tentacle_id,
          data: a_string_including("hello-reattach")
        )
      ).at_least(:once)
    end
  end

  describe "crash during downtime" do
    it "finalizes the session as exited and does not reattach when the child died" do
      spawned = TentacleRuntime.start(tentacle_id: tentacle_id, command: ["cat"])
      child_pid = spawned.pid

      TentacleRuntime.shutdown!(grace: 2)
      sleep 0.2

      Process.kill("KILL", child_pid)
      wait_until(2) { !process_alive?(child_pid) }
      expect(process_alive?(child_pid)).to be(false)

      TentacleRuntime.bootstrap_sessions!
      expect(TentacleRuntime.get(tentacle_id)).to be_nil
      expect(TentacleSession.alive.where(tentacle_note_id: tentacle_id)).to be_empty

      # bootstrap_sessions! → reattach_record returns false for dead pid →
      # finalize_dead_record → mark_ended!(reason: "missing_pid"|"crash") →
      # status "exited". "unknown" is reserved for reattach that raised.
      record = TentacleSession.where(tentacle_note_id: tentacle_id).order(:created_at).last
      expect(record.status).to eq("exited")
      expect(record.exit_reason).to be_in(%w[missing_pid crash])
      expect(record.ended_at).to be_present
    end
  end

  describe "orphan socket sweep" do
    # cleanup_orphaned_sockets refuses to sweep until BOOTSTRAP_SENTINEL
    # exists (guard against a tick firing before reattach knows which
    # records belong to this process tree). The real path writes it at
    # the end of bootstrap_sessions!; in the specs we touch it directly
    # to isolate the sweep from the reattach flow.
    before do
      FileUtils.touch(File.join(@runtime_dir, TentacleRuntime::BOOTSTRAP_SENTINEL))
    end

    it "removes socket + pidfile pairs with no matching alive record" do
      orphan_name = "orphan-#{SecureRandom.hex(4)}"
      orphan_sock = File.join(@runtime_dir, "#{orphan_name}.sock")
      orphan_pid = File.join(@runtime_dir, "#{orphan_name}.pid")
      File.write(orphan_sock, "")
      File.write(orphan_pid, "99999999")

      Tentacles::SupervisorJob.new.perform

      expect(File.exist?(orphan_sock)).to be(false)
      expect(File.exist?(orphan_pid)).to be(false)
    end

    it "preserves sockets belonging to alive records" do
      spawned = TentacleRuntime.start(tentacle_id: tentacle_id, command: ["cat"])
      socket_path = spawned.dtach.socket_path
      expect(File.exist?(socket_path)).to be(true)

      Tentacles::SupervisorJob.new.perform

      expect(File.exist?(socket_path)).to be(true)
      expect(spawned.alive?).to be(true)
    end
  end

  private

  def with_dtach_env(dir)
    prev_flag = ENV["NEURAMD_FEATURE_DTACH"]
    prev_dir = ENV["NEURAMD_TENTACLE_RUNTIME_DIR"]
    ENV["NEURAMD_FEATURE_DTACH"] = "on"
    ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = dir
    Tentacles::DtachWrapper.reset_availability_cache!
    yield
  ensure
    prev_flag.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = prev_flag
    prev_dir.nil? ? ENV.delete("NEURAMD_TENTACLE_RUNTIME_DIR") : ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = prev_dir
    Tentacles::DtachWrapper.reset_availability_cache!
  end

  # Safety net — if an assertion aborted mid-test the child `cat` would
  # otherwise outlive the example, holding the tmpdir open and leaking
  # fds. Walk the pidfiles and SIGKILL anything still breathing.
  def cleanup_leftover_children(dir)
    Dir.glob(File.join(dir, "*.pid")).each do |pid_file|
      pid = Integer(File.read(pid_file).strip)
      Process.kill("KILL", pid)
    rescue ArgumentError, Errno::ESRCH, Errno::ENOENT
    end
  end

  def wait_until(timeout)
    deadline = Time.current + timeout
    until yield
      break if Time.current > deadline
      sleep 0.05
    end
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
