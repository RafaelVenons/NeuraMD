require "rails_helper"

RSpec.describe TentacleRuntime do
  let(:tentacle_id) { SecureRandom.uuid }

  before do
    allow(TentacleChannel).to receive(:broadcast_output)
    allow(TentacleChannel).to receive(:broadcast_exit)
  end

  after { described_class.reset! }

  describe ".dtach_enabled?" do
    {
      nil => false,
      "" => false,
      "off" => false,
      "0" => false,
      "true" => false,
      "on" => true,
      "ON" => true,
      "On" => true
    }.each do |env_value, expected|
      it "returns #{expected} when NEURAMD_FEATURE_DTACH=#{env_value.inspect}" do
        original = ENV["NEURAMD_FEATURE_DTACH"]
        env_value.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = env_value
        begin
          expect(described_class.dtach_enabled?).to eq(expected)
        ensure
          original.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = original
        end
      end
    end
  end

  describe "dtach mode (feature flag on)" do
    let(:note) { create(:note, title: "Dtach Note") }
    let(:tentacle_id) { note.id }

    around do |example|
      original = ENV["NEURAMD_FEATURE_DTACH"]
      ENV["NEURAMD_FEATURE_DTACH"] = "on"
      example.run
    ensure
      original.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = original
    end

    let(:wrapper) do
      instance_double(
        Tentacles::DtachWrapper,
        socket_path: "/run/nm-tentacles/#{tentacle_id}.sock",
        pid_path: "/run/nm-tentacles/#{tentacle_id}.pid",
        pid: 7777
      )
    end

    before do
      allow(Tentacles::DtachWrapper).to receive(:new).and_return(wrapper)
      allow(wrapper).to receive(:alive?).and_return(false, true)
      allow(wrapper).to receive(:spawn)
      allow(wrapper).to receive(:stop).and_return(:already_gone)
      reader, writer = IO.pipe
      allow(PTY).to receive(:spawn)
        .with("dtach", "-a", wrapper.socket_path, "-E", "-z")
        .and_return([reader, writer, 9000])
      # Skip the background reader thread in these unit tests — the
      # teardown path would have the reader thread touch AR across the
      # DatabaseCleaner boundary. Exit-time behaviour has its own
      # coverage in the PTY-mode specs above.
      allow_any_instance_of(described_class::Session).to receive(:start_reader)
    end

    it "spawns via DtachWrapper when the session is not yet alive" do
      expect(wrapper).to receive(:spawn).with(["sleep", "30"], hash_including(cwd: nil))
      described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
    end

    it "creates a TentacleSession record on first spawn" do
      expect {
        described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      }.to change { TentacleSession.alive.count }.by(1)

      record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
      expect(record).not_to be_nil
      expect(record.dtach_socket).to eq(wrapper.socket_path)
      expect(record.pid).to eq(7777)
      expect(record.command).to eq("sleep 30")
    end

    it "attaches via PTY.spawn on dtach -a so resize ioctl propagates" do
      expect(PTY).to receive(:spawn).with("dtach", "-a", wrapper.socket_path, "-E", "-z")
      described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
    end

    it "reuses the existing detached session without re-spawning when wrapper.alive?" do
      create(:tentacle_session,
        tentacle_note_id: tentacle_id,
        dtach_socket: wrapper.socket_path,
        pid_file: wrapper.pid_path,
        pid: 7777,
        command: "sleep 30",
        status: "alive")
      allow(wrapper).to receive(:alive?).and_return(true)
      expect(wrapper).not_to receive(:spawn)
      expect { described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"]) }
        .not_to change { TentacleSession.count }
    end

    it "stores the child pid (from wrapper.pid), not the attach proxy pid" do
      session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      expect(session.pid).to eq(7777)
    end

    it "exposes dtach_mode? true" do
      session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      expect(session.dtach_mode?).to be true
    end

    describe "#stop(detach_only: true)" do
      # Clear SESSIONS at the end of each detach_only example so the
      # top-level `after { reset! }` does not try to kill (via
      # wrapper.stop) the session we intentionally left alive.
      after { described_class::SESSIONS.clear }

      it "closes streams without calling wrapper.stop and without firing on_exit" do
        on_exit_called = false
        session = described_class.start(
          tentacle_id: tentacle_id,
          command: ["sleep", "30"],
          on_exit: ->(**) { on_exit_called = true }
        )

        session.stop(detach_only: true)

        expect(wrapper).not_to have_received(:stop)
        expect(on_exit_called).to be false
        expect(session.instance_variable_get(:@reader).closed?).to be true
      end

      it "does not mark the TentacleSession record as ended" do
        session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
        record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
        expect(record).not_to be_nil

        session.stop(detach_only: true)

        expect(record.reload.status).to eq("alive")
        expect(record.ended_at).to be_nil
      end

      it "touches last_seen_at on the record" do
        session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
        record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
        record.update_column(:last_seen_at, 1.hour.ago)

        session.stop(detach_only: true)
        expect(record.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
      end
    end

    describe "spawn/persist atomicity" do
      it "stops the just-spawned dtach child and re-raises when persisting the TentacleSession fails" do
        allow(wrapper).to receive(:alive?).and_return(false)
        allow(wrapper).to receive(:spawn)
        allow(wrapper).to receive(:cleanup)
        allow(TentacleSession).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(TentacleSession.new)
        )

        expect(wrapper).to receive(:stop).with(hash_including(:grace)).and_return(:stopped)

        expect {
          described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(described_class::SESSIONS[tentacle_id]).to be_nil
        expect(TentacleSession.where(tentacle_note_id: tentacle_id).count).to eq(0)
      end

      it "persists a TentacleSession record when attaching to a pre-existing dtach socket that has no record" do
        allow(wrapper).to receive(:alive?).and_return(true)
        allow(Rails.logger).to receive(:warn)

        expect {
          described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
        }.to change { TentacleSession.alive.where(tentacle_note_id: tentacle_id).count }.by(1)

        expect(wrapper).not_to have_received(:spawn) if wrapper.respond_to?(:spawn)
      end

      it "does not create a duplicate record when attaching to a pre-existing dtach socket whose record already exists" do
        create(:tentacle_session,
          tentacle_note_id: tentacle_id,
          dtach_socket: wrapper.socket_path,
          pid_file: wrapper.pid_path,
          pid: 7777,
          command: "sleep 30",
          status: "alive")
        allow(wrapper).to receive(:alive?).and_return(true)

        expect {
          described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
        }.not_to change { TentacleSession.where(tentacle_note_id: tentacle_id).count }
      end
    end

    describe "#stop when the child survives SIGKILL" do
      after { described_class::SESSIONS.clear }

      it "does not fire on_exit and marks the TentacleSession unknown when wrapper.stop returns :still_alive" do
        on_exit_called = false
        session = described_class.start(
          tentacle_id: tentacle_id,
          command: ["sleep", "30"],
          on_exit: ->(**) { on_exit_called = true }
        )
        record = TentacleSession.alive.find_by(tentacle_note_id: tentacle_id)
        expect(record).not_to be_nil

        allow(wrapper).to receive(:stop).and_return(:still_alive)
        allow(Rails.logger).to receive(:error)

        session.stop(grace: 0.05)

        expect(on_exit_called).to be false
        expect(record.reload.status).to eq("unknown")
        expect(record.reload.ended_at).to be_nil
      end
    end
  end

  describe ".detach_all_for_shutdown" do
    before { described_class::SESSIONS.clear }

    it "calls stop(detach_only: true) on each live session and clears SESSIONS" do
      session1 = instance_double(described_class::Session, stop: true)
      session2 = instance_double(described_class::Session, stop: true)
      described_class::SESSIONS["a"] = session1
      described_class::SESSIONS["b"] = session2

      expect(session1).to receive(:stop).with(detach_only: true)
      expect(session2).to receive(:stop).with(detach_only: true)

      result = described_class.detach_all_for_shutdown
      expect(result).to match_array(%w[a b])
      expect(described_class::SESSIONS).to be_empty
    end

    it "continues when a session raises" do
      good = instance_double(described_class::Session, stop: true)
      bad = instance_double(described_class::Session)
      allow(bad).to receive(:stop).and_raise("boom")
      described_class::SESSIONS["good"] = good
      described_class::SESSIONS["bad"] = bad

      expect { described_class.detach_all_for_shutdown }.not_to raise_error
      expect(described_class::SESSIONS).to be_empty
    end
  end

  describe ".shutdown!" do
    it "routes to detach_all_for_shutdown when dtach is enabled" do
      allow(described_class).to receive(:dtach_enabled?).and_return(true)
      expect(described_class).to receive(:detach_all_for_shutdown).and_return([])
      expect(described_class).not_to receive(:graceful_stop_all)
      described_class.shutdown!(grace: 7)
    end

    it "routes to graceful_stop_all when dtach is disabled" do
      allow(described_class).to receive(:dtach_enabled?).and_return(false)
      expect(described_class).to receive(:graceful_stop_all).with(grace: 7).and_return([])
      expect(described_class).not_to receive(:detach_all_for_shutdown)
      described_class.shutdown!(grace: 7)
    end
  end

  describe ".bootstrap_sessions!" do
    let(:note) { create(:note, title: "Bootstrap Note") }

    it "returns 0 and does nothing when dtach is disabled" do
      allow(described_class).to receive(:dtach_enabled?).and_return(false)
      create(:tentacle_session, tentacle_note_id: note.id)
      expect(described_class.bootstrap_sessions!).to eq(0)
      expect(described_class::SESSIONS).to be_empty
    end

    context "with dtach enabled" do
      around do |example|
        Dir.mktmpdir do |dir|
          @runtime_dir = dir
          original = ENV["NEURAMD_FEATURE_DTACH"]
          original_runtime = ENV["NEURAMD_TENTACLE_RUNTIME_DIR"]
          ENV["NEURAMD_FEATURE_DTACH"] = "on"
          ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = dir
          example.run
        ensure
          original.nil? ? ENV.delete("NEURAMD_FEATURE_DTACH") : ENV["NEURAMD_FEATURE_DTACH"] = original
          original_runtime.nil? ? ENV.delete("NEURAMD_TENTACLE_RUNTIME_DIR") : ENV["NEURAMD_TENTACLE_RUNTIME_DIR"] = original_runtime
        end
      end

      let(:socket_path) { File.join(@runtime_dir, "#{note.id}.sock") }
      let(:pid_path) { File.join(@runtime_dir, "#{note.id}.pid") }

      let(:wrapper) do
        instance_double(
          Tentacles::DtachWrapper,
          socket_path: socket_path,
          pid_path: pid_path,
          pid: 8888
        )
      end

      before do
        allow(Tentacles::DtachWrapper).to receive(:new).and_return(wrapper)
        allow(wrapper).to receive(:stop).and_return(:already_gone)
        allow(wrapper).to receive(:cleanup)
        reader, writer = IO.pipe
        allow(PTY).to receive(:spawn).and_return([reader, writer, 9100])
        allow_any_instance_of(described_class::Session).to receive(:start_reader)
      end

      it "reattaches sessions whose child is still alive" do
        record = create(:tentacle_session,
          tentacle_note_id: note.id,
          dtach_socket: wrapper.socket_path,
          command: "bash -l")
        allow(wrapper).to receive(:socket_exists?).and_return(true)
        allow(wrapper).to receive(:alive?).and_return(true)

        reattached = described_class.bootstrap_sessions!

        expect(reattached).to eq(1)
        expect(described_class::SESSIONS[note.id]).to be_a(described_class::Session)
        expect(record.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
      end

      it "finalizes a known-dead record with reason=missing_pid when the socket is gone" do
        record = create(:tentacle_session,
          tentacle_note_id: note.id,
          dtach_socket: wrapper.socket_path)
        allow(wrapper).to receive(:socket_exists?).and_return(false)
        allow(wrapper).to receive(:alive?).and_return(false)
        expect(wrapper).to receive(:cleanup)

        described_class.bootstrap_sessions!

        record.reload
        expect(record.status).to eq("exited")
        expect(record.exit_reason).to eq("missing_pid")
        expect(record.ended_at).to be_within(5.seconds).of(Time.current)
        expect(described_class::SESSIONS).to be_empty
      end

      it "finalizes a known-dead record with reason=crash when socket survives but pid is gone" do
        record = create(:tentacle_session,
          tentacle_note_id: note.id,
          dtach_socket: wrapper.socket_path)
        allow(wrapper).to receive(:socket_exists?).and_return(true)
        allow(wrapper).to receive(:alive?).and_return(false)
        expect(wrapper).to receive(:cleanup)

        described_class.bootstrap_sessions!

        record.reload
        expect(record.status).to eq("exited")
        expect(record.exit_reason).to eq("crash")
      end

      it "falls back to mark_unknown! when reattach raises unexpectedly" do
        record = create(:tentacle_session,
          tentacle_note_id: note.id,
          dtach_socket: wrapper.socket_path)
        allow(wrapper).to receive(:socket_exists?).and_raise(StandardError, "io boom")

        described_class.bootstrap_sessions!

        expect(record.reload.status).to eq("unknown")
      end

      it "writes the bootstrap sentinel to the runtime dir when complete" do
        described_class.bootstrap_sessions!
        sentinel = File.join(@runtime_dir, TentacleRuntime::BOOTSTRAP_SENTINEL)
        expect(File.exist?(sentinel)).to be true
      end

      it "ignores records that are already marked exited" do
        create(:tentacle_session, :exited, tentacle_note_id: note.id, dtach_socket: wrapper.socket_path)
        expect(wrapper).not_to receive(:socket_exists?)
        expect(described_class.bootstrap_sessions!).to eq(0)
      end

      it "reconstructs an on_exit callback from the stored persistence descriptor so a natural exit after reattach still persists the transcript" do
        user = create(:user)
        create(:tentacle_session,
          tentacle_note_id: note.id,
          dtach_socket: wrapper.socket_path,
          command: "bash -l",
          metadata: {"persistence" => {"kind" => "web", "author_id" => user.id}})
        allow(wrapper).to receive(:socket_exists?).and_return(true)
        allow(wrapper).to receive(:alive?).and_return(true)

        described_class.bootstrap_sessions!

        session = described_class::SESSIONS[note.id]
        expect(session).not_to be_nil
        session.append_to_transcript("reattached transcript")

        expect(Tentacles::TranscriptService).to receive(:persist).with(
          hash_including(
            note: note,
            transcript: "reattached transcript",
            author: user
          )
        )

        session.fire_on_exit(exit_status: 0)
      end
    end
  end

  describe ".start" do
    it "spawns a subprocess and streams stdout through the channel" do
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

      session = described_class.start(
        tentacle_id: tentacle_id,
        command: ["echo", "hello from tentacle"]
      )

      expect(session).to be_a(TentacleRuntime::Session)
      expect(session.pid).to be_a(Integer)
      expect(wait_until { received.join.include?("hello from tentacle") }).to be_truthy
    end

    it "reuses the same session when called twice with the same id" do
      first = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "1"])
      second = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

      expect(second.pid).to eq(first.pid)
    end

    it "honors the cwd option when provided" do
      Dir.mktmpdir do |tmp|
        received = []
        allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

        described_class.start(
          tentacle_id: tentacle_id,
          command: ["pwd"],
          cwd: tmp
        )

        expect(wait_until { received.join.include?(File.realpath(tmp)) }).to be_truthy
      end
    end

    it "writes initial_prompt to stdin after boot when provided" do
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

      described_class.start(
        tentacle_id: tentacle_id,
        command: ["cat"],
        initial_prompt: "hello tentacle"
      )

      expect(wait_until { received.join.include?("hello tentacle") }).to be_truthy
    end

    it "does not crash when initial_prompt is nil" do
      expect {
        described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"], initial_prompt: nil)
      }.not_to raise_error
    end

    it "exports NEURAMD_TENTACLE_ID in the child process env" do
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

      described_class.start(
        tentacle_id: tentacle_id,
        command: ["sh", "-c", "printf %s \"$NEURAMD_TENTACLE_ID\""]
      )

      expect(wait_until { received.join.include?(tentacle_id) }).to be_truthy
    end

    it "scrubs Rails env vars so a child rspec cannot inherit RAILS_ENV=development" do
      # Regression: a tentacle spawned from the dev server used to inherit
      # RAILS_ENV=development; any `bundle exec rspec` child then ran against
      # the dev DB and DatabaseCleaner.clean_with(:truncation) wiped the acervo.
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

      previous = {"RAILS_ENV" => ENV["RAILS_ENV"], "RACK_ENV" => ENV["RACK_ENV"], "DATABASE_URL" => ENV["DATABASE_URL"]}
      ENV["RAILS_ENV"] = "development"
      ENV["RACK_ENV"] = "development"
      ENV["DATABASE_URL"] = "postgres://leaked/db"
      begin
        described_class.start(
          tentacle_id: tentacle_id,
          command: ["sh", "-c", 'printf "rails_env=%s rack_env=%s database_url=%s" "${RAILS_ENV:-empty}" "${RACK_ENV:-empty}" "${DATABASE_URL:-empty}"']
        )
      ensure
        previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end

      expect(wait_until { received.join.include?("rails_env=") }).to be_truthy
      combined = received.join
      expect(combined).to include("rails_env=empty")
      expect(combined).to include("rack_env=empty")
      expect(combined).to include("database_url=empty")
    end

    it "propagates RAILS_ENV=production to the child when the server runs in production" do
      # In production, the inverse of the dev scrubbing is required: the
      # child (e.g. bin/mcp-server booting Rails) must see RAILS_ENV=production,
      # otherwise it falls back to development and tries to load dev-only
      # gems missing from the production bundle.
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      described_class.start(
        tentacle_id: tentacle_id,
        command: ["sh", "-c", 'printf "rails_env=%s rack_env=%s" "${RAILS_ENV:-empty}" "${RACK_ENV:-empty}"']
      )

      expect(wait_until { received.join.include?("rails_env=") }).to be_truthy
      combined = received.join
      expect(combined).to include("rails_env=production")
      expect(combined).to include("rack_env=production")
    end
  end

  describe ".write" do
    it "forwards input to the subprocess stdin" do
      received = []
      allow(TentacleChannel).to receive(:broadcast_output) { |data:, **| received << data }

      described_class.start(tentacle_id: tentacle_id, command: ["cat"])
      sleep(0.05)
      described_class.write(tentacle_id: tentacle_id, data: "ping\n")

      expect(wait_until { received.join.include?("ping") }).to be_truthy
    end

    it "is a no-op for an unknown tentacle" do
      expect { described_class.write(tentacle_id: "unknown", data: "x") }.not_to raise_error
    end
  end

  describe ".stop" do
    it "terminates the subprocess and removes it from the registry" do
      session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      pid = session.pid

      described_class.stop(tentacle_id: tentacle_id)

      expect(described_class.get(tentacle_id)).to be_nil
      expect(wait_until { !process_alive?(pid) }).to be_truthy
    end

    it "is a no-op for an unknown tentacle" do
      expect { described_class.stop(tentacle_id: "unknown") }.not_to raise_error
    end
  end

  describe "on_exit callback" do
    it "fires once with the captured transcript when the subprocess exits" do
      calls = Concurrent::Array.new
      described_class.start(
        tentacle_id: tentacle_id,
        command: ["sh", "-c", "printf 'line1\\nline2\\n'"],
        on_exit: ->(transcript:, **meta) { calls << [transcript, meta] }
      )

      expect(wait_until { calls.any? }).to be_truthy
      transcript, meta = calls.first
      expect(transcript).to include("line1")
      expect(transcript).to include("line2")
      expect(meta[:started_at]).to be_a(Time)
      expect(meta[:ended_at]).to be_a(Time)
      expect(meta[:command]).to eq(["sh", "-c", "printf 'line1\\nline2\\n'"])
      expect(calls.size).to eq(1)
    end

    it "fires when .stop is invoked before the process exits naturally" do
      calls = Concurrent::Array.new
      described_class.start(
        tentacle_id: tentacle_id,
        command: ["sh", "-c", "printf ready; sleep 30"],
        on_exit: ->(transcript:, **) { calls << transcript }
      )
      expect(wait_until { described_class.get(tentacle_id) }).to be_truthy
      sleep(0.1)

      described_class.stop(tentacle_id: tentacle_id)

      expect(wait_until { calls.any? }).to be_truthy
      expect(calls.first).to include("ready")
      expect(calls.size).to eq(1)
    end
  end

  describe "metric emission" do
    let(:emissions) { Concurrent::Array.new }

    before do
      allow(Neuramd::Metrics).to receive(:emit) do |type, payload|
        emissions << [type, payload]
        nil
      end
    end

    def emitted_reasons
      emissions.select { |type, _| type == "tentacle_exit" }.map { |_, p| p[:reason] }
    end

    it "emits tentacle_spawn when a new session starts" do
      described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])
      spawn_calls = emissions.select { |type, _| type == "tentacle_spawn" }
      expect(spawn_calls.size).to eq(1)
      expect(spawn_calls.first[1]).to include(tentacle_id: tentacle_id.to_s, command: "sleep")
    end

    it "does not emit tentacle_spawn when an existing live session is reused" do
      described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      described_class.start(tentacle_id: tentacle_id, command: ["sleep", "30"])
      expect(emissions.count { |type, _| type == "tentacle_spawn" }).to eq(1)
    end

    it "emits tentacle_exit with reason=graceful on a clean exit" do
      described_class.start(tentacle_id: tentacle_id, command: ["sh", "-c", "exit 0"])
      expect(wait_until { emitted_reasons.include?("graceful") }).to be_truthy
    end

    it "emits tentacle_exit with reason=crash on non-zero exit" do
      described_class.start(tentacle_id: tentacle_id, command: ["sh", "-c", "exit 42"])
      expect(wait_until { emitted_reasons.include?("crash") }).to be_truthy
    end

    it "emits tentacle_exit with reason=forced when stop escalates to SIGKILL" do
      described_class.start(
        tentacle_id: tentacle_id,
        command: ["sh", "-c", "trap '' TERM; sleep 30"]
      )
      expect(wait_until { described_class.get(tentacle_id) }).to be_truthy
      sleep(0.1)

      described_class.graceful_stop_all(grace: 1)

      expect(wait_until { emitted_reasons.include?("forced") }).to be_truthy
    end
  end

  describe ".graceful_stop_all" do
    it "returns an empty list when there are no sessions" do
      expect(described_class.graceful_stop_all(grace: 1)).to eq([])
    end

    it "stops each alive session, fires on_exit once per session, and clears SESSIONS" do
      transcripts = Concurrent::Array.new
      id1 = SecureRandom.uuid
      id2 = SecureRandom.uuid

      described_class.start(
        tentacle_id: id1,
        command: ["sh", "-c", "printf one; sleep 30"],
        on_exit: ->(transcript:, **) { transcripts << [id1, transcript] }
      )
      described_class.start(
        tentacle_id: id2,
        command: ["sh", "-c", "printf two; sleep 30"],
        on_exit: ->(transcript:, **) { transcripts << [id2, transcript] }
      )

      expect(wait_until { described_class.get(id1) && described_class.get(id2) }).to be_truthy
      sleep(0.1)

      stopped = described_class.graceful_stop_all(grace: 2)

      expect(stopped).to match_array([id1.to_s, id2.to_s])
      expect(TentacleRuntime::SESSIONS).to be_empty
      expect(wait_until { transcripts.size >= 2 }).to be_truthy
      expect(transcripts.map(&:first)).to match_array([id1, id2])
    end

    it "escalates to SIGKILL when the child ignores SIGTERM" do
      id = SecureRandom.uuid
      exits = Concurrent::Array.new

      described_class.start(
        tentacle_id: id,
        command: ["sh", "-c", "trap '' TERM; sleep 30"],
        on_exit: ->(**meta) { exits << meta }
      )
      expect(wait_until { described_class.get(id) }).to be_truthy
      sleep(0.2)
      pid = described_class.get(id).pid

      stopped = described_class.graceful_stop_all(grace: 1)

      expect(stopped).to eq([id.to_s])
      expect(wait_until { !process_alive?(pid) }).to be_truthy
      expect(exits.size).to eq(1)
    end
  end

  describe "live transcript cap" do
    it "keeps only the tail when the buffer exceeds LIVE_TRANSCRIPT_CAP" do
      session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])
      cap = TentacleRuntime::Session::LIVE_TRANSCRIPT_CAP

      session.append_to_transcript("A" * 1_000)
      session.append_to_transcript("B" * (cap + 500))

      transcript = session.transcript
      expect(transcript).to start_with("[live-truncated")
      expect(transcript).to include("1500 leading bytes")
      expect(transcript.bytesize).to be <= cap + 128
      expect(transcript).not_to include("A")
      expect(transcript.count("B")).to eq(cap)
    end

    it "does not mark truncation when under the cap" do
      session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

      session.append_to_transcript("hello world")

      expect(session.transcript).to eq("hello world")
    end
  end

  def wait_until(timeout: 3.0, interval: 0.05)
    deadline = Time.current + timeout
    loop do
      result = yield
      return result if result
      break if Time.current > deadline
      sleep(interval)
    end
    false
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end
end
