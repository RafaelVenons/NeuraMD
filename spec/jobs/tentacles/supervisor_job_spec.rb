require "rails_helper"

RSpec.describe Tentacles::SupervisorJob, type: :job do
  before { TentacleRuntime::SESSIONS.clear }
  after { TentacleRuntime::SESSIONS.clear }

  def session_double(alive:, started_at: 10.seconds.ago)
    instance_double(TentacleRuntime::Session, alive?: alive, started_at: started_at)
  end

  describe "#perform" do
    it "does nothing when SESSIONS is empty" do
      expect(TentacleRuntime).not_to receive(:stop)
      described_class.perform_now
    end

    it "leaves live sessions untouched" do
      TentacleRuntime::SESSIONS["abc"] = session_double(alive: true)
      expect(TentacleRuntime).not_to receive(:stop)
      described_class.perform_now
    end

    it "reaps a dead session past the grace period" do
      TentacleRuntime::SESSIONS["zombie"] = session_double(alive: false, started_at: 30.seconds.ago)
      expect(TentacleRuntime).to receive(:stop).with(tentacle_id: "zombie")
      described_class.perform_now
    end

    it "skips a dead session still inside the grace period" do
      TentacleRuntime::SESSIONS["booting"] = session_double(alive: false, started_at: 1.second.ago)
      expect(TentacleRuntime).not_to receive(:stop)
      described_class.perform_now
    end

    it "only reaps the dead sessions when mixed with live ones" do
      TentacleRuntime::SESSIONS["live"] = session_double(alive: true)
      TentacleRuntime::SESSIONS["dead"] = session_double(alive: false, started_at: 30.seconds.ago)
      expect(TentacleRuntime).to receive(:stop).with(tentacle_id: "dead")
      expect(TentacleRuntime).not_to receive(:stop).with(tentacle_id: "live")
      described_class.perform_now
    end

    it "swallows errors from TentacleRuntime.stop and continues reaping" do
      TentacleRuntime::SESSIONS["bad"] = session_double(alive: false, started_at: 30.seconds.ago)
      TentacleRuntime::SESSIONS["good"] = session_double(alive: false, started_at: 30.seconds.ago)
      allow(TentacleRuntime).to receive(:stop).with(tentacle_id: "bad").and_raise(StandardError, "boom")
      expect(TentacleRuntime).to receive(:stop).with(tentacle_id: "good")
      expect(Rails.logger).to receive(:error).with(/bad/)

      expect { described_class.perform_now }.not_to raise_error
    end
  end

  describe "dtach mode paths" do
    let(:note) { create(:note, title: "SupervisorNote") }
    let(:runtime_dir) { @tmpdir }

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        original_env = ENV["NEURAMD_FEATURE_DTACH"]
        original_runtime = ENV["NEURAMD_TENTACLE_RUNTIME_DIR"]
        ENV["NEURAMD_FEATURE_DTACH"] = "on"
        ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = dir
        example.run
      ensure
        original_env.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = original_env
        original_runtime.nil? ? ENV.delete("NEURAMD_TENTACLE_RUNTIME_DIR") : ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = original_runtime
      end
    end

    def make_record(note_id:, last_seen: nil)
      socket = File.join(runtime_dir, "#{note_id}.sock")
      create(:tentacle_session,
        tentacle_note_id: note_id,
        dtach_socket: socket,
        pid_file: socket.sub(/\.sock\z/, ".pid"),
        last_seen_at: last_seen)
    end

    def stub_wrapper(alive:, socket_exists:)
      wrapper = instance_double(Tentacles::DtachWrapper,
        alive?: alive,
        socket_exists?: socket_exists)
      allow(wrapper).to receive(:cleanup)
      allow(Tentacles::DtachWrapper).to receive(:new).and_return(wrapper)
      wrapper
    end

    describe "reap_stale_db_sessions" do
      it "does not run when dtach is disabled" do
        ENV["NEURAMD_FEATURE_DTACH"] = "off"
        record = make_record(note_id: note.id, last_seen: 1.hour.ago)
        expect(Tentacles::DtachWrapper).not_to receive(:new)
        described_class.perform_now
        expect(record.reload.status).to eq("alive")
      end

      it "skips records whose last_seen_at is recent" do
        make_record(note_id: note.id, last_seen: 1.second.ago)
        expect(Tentacles::DtachWrapper).not_to receive(:new)
        described_class.perform_now
      end

      it "touches last_seen_at when the wrapper is alive" do
        record = make_record(note_id: note.id, last_seen: 1.hour.ago)
        stub_wrapper(alive: true, socket_exists: true)

        described_class.perform_now
        expect(record.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
        expect(record.status).to eq("alive")
      end

      it "marks the record ended with reason=missing_pid when the socket is gone" do
        record = make_record(note_id: note.id, last_seen: 1.hour.ago)
        wrapper = stub_wrapper(alive: false, socket_exists: false)
        expect(wrapper).to receive(:cleanup)

        described_class.perform_now

        record.reload
        expect(record.status).to eq("exited")
        expect(record.exit_reason).to eq("missing_pid")
      end

      it "marks the record ended with reason=crash when the socket is stale but pid dead" do
        record = make_record(note_id: note.id, last_seen: 1.hour.ago)
        wrapper = stub_wrapper(alive: false, socket_exists: true)
        expect(wrapper).to receive(:cleanup)

        described_class.perform_now

        record.reload
        expect(record.status).to eq("exited")
        expect(record.exit_reason).to eq("crash")
      end
    end

    describe "cleanup_orphaned_sockets" do
      def write_bootstrap_sentinel!
        FileUtils.touch(File.join(runtime_dir, TentacleRuntime::BOOTSTRAP_SENTINEL))
      end

      it "removes socket + pidfile pairs that have no matching alive record" do
        write_bootstrap_sentinel!
        orphan = File.join(runtime_dir, "orphan.sock")
        pidfile = File.join(runtime_dir, "orphan.pid")
        File.write(orphan, "")
        dead_pid = spawn("/bin/true")
        Process.wait(dead_pid)
        File.write(pidfile, dead_pid.to_s)

        described_class.perform_now

        expect(File.exist?(orphan)).to be false
        expect(File.exist?(pidfile)).to be false
      end

      it "leaves sockets listed by alive records intact" do
        write_bootstrap_sentinel!
        kept = File.join(runtime_dir, "#{note.id}.sock")
        File.write(kept, "")
        make_record(note_id: note.id, last_seen: 1.second.ago)

        described_class.perform_now

        expect(File.exist?(kept)).to be true
      end

      it "does not sweep until the bootstrap sentinel exists" do
        orphan = File.join(runtime_dir, "orphan.sock")
        File.write(orphan, "")

        described_class.perform_now

        expect(File.exist?(orphan)).to be true
      end

      it "protects sockets of records marked unknown by bootstrap" do
        write_bootstrap_sentinel!
        kept = File.join(runtime_dir, "#{note.id}.sock")
        File.write(kept, "")
        record = make_record(note_id: note.id, last_seen: 1.hour.ago)
        record.mark_unknown!

        described_class.perform_now

        expect(File.exist?(kept)).to be true
      end

      it "skips sockets whose companion pidfile points to a live pid" do
        write_bootstrap_sentinel!
        orphan = File.join(runtime_dir, "live-orphan.sock")
        pidfile = File.join(runtime_dir, "live-orphan.pid")
        File.write(orphan, "")
        File.write(pidfile, Process.pid.to_s)

        described_class.perform_now

        expect(File.exist?(orphan)).to be true
        expect(File.exist?(pidfile)).to be true
      end

      it "removes sockets whose companion pidfile points to a dead pid" do
        write_bootstrap_sentinel!
        orphan = File.join(runtime_dir, "dead-orphan.sock")
        pidfile = File.join(runtime_dir, "dead-orphan.pid")
        File.write(orphan, "")
        dead_pid = spawn("/bin/true")
        Process.wait(dead_pid)
        File.write(pidfile, dead_pid.to_s)

        described_class.perform_now

        expect(File.exist?(orphan)).to be false
        expect(File.exist?(pidfile)).to be false
      end

      it "is a no-op when the runtime dir does not exist" do
        missing_dir = File.join(runtime_dir, "does-not-exist-#{SecureRandom.hex(4)}")
        ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = missing_dir
        expect { described_class.perform_now }.not_to raise_error
      end
    end
  end
end
