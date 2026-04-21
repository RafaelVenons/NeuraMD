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
