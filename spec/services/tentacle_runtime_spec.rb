require "rails_helper"

RSpec.describe TentacleRuntime do
  let(:tentacle_id) { SecureRandom.uuid }

  before do
    allow(TentacleChannel).to receive(:broadcast_output)
    allow(TentacleChannel).to receive(:broadcast_exit)
  end

  after { described_class.reset! }

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
