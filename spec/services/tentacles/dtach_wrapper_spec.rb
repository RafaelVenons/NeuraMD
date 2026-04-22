require "rails_helper"
require "tmpdir"

RSpec.describe Tentacles::DtachWrapper do
  around do |example|
    Dir.mktmpdir do |dir|
      @runtime_dir = dir
      described_class.reset_availability_cache!
      example.run
    ensure
      described_class.reset_availability_cache!
    end
  end

  let(:session_id) { "test-#{SecureRandom.hex(4)}" }
  let(:wrapper) { described_class.new(session_id: session_id, runtime_dir: @runtime_dir) }

  describe "construction" do
    it "exposes socket/pid paths under the runtime dir" do
      expect(wrapper.socket_path).to eq(File.join(@runtime_dir, "#{session_id}.sock"))
      expect(wrapper.pid_path).to eq(File.join(@runtime_dir, "#{session_id}.pid"))
    end

    it "rejects a blank session_id" do
      expect { described_class.new(session_id: "", runtime_dir: @runtime_dir) }
        .to raise_error(ArgumentError, /session_id/)
      expect { described_class.new(session_id: "   ", runtime_dir: @runtime_dir) }
        .to raise_error(ArgumentError, /session_id/)
    end
  end

  describe "#pid" do
    it "returns nil when the pid file does not exist" do
      expect(wrapper.pid).to be_nil
    end

    it "returns nil for an empty or malformed pid file" do
      File.write(wrapper.pid_path, "")
      expect(wrapper.pid).to be_nil
      File.write(wrapper.pid_path, "not-a-number")
      expect(wrapper.pid).to be_nil
    end

    it "parses a valid integer pid from the pid file" do
      File.write(wrapper.pid_path, "12345\n")
      expect(wrapper.pid).to eq(12345)
    end
  end

  describe "#alive?" do
    it "is false when there is no pid file" do
      expect(wrapper.alive?).to be false
    end

    it "is false when the pid does not correspond to a live process" do
      File.write(wrapper.pid_path, "999999999")
      expect(wrapper.alive?).to be false
    end

    it "is true when the pid corresponds to this process itself" do
      File.write(wrapper.pid_path, Process.pid.to_s)
      expect(wrapper.alive?).to be true
    end
  end

  describe "#cleanup" do
    it "removes socket and pid file paths idempotently" do
      FileUtils.touch(wrapper.pid_path)
      File.open(wrapper.socket_path, "w") { |f| f.write("x") }
      wrapper.cleanup
      expect(File.exist?(wrapper.pid_path)).to be false
      expect(File.exist?(wrapper.socket_path)).to be false

      expect { wrapper.cleanup }.not_to raise_error
    end
  end

  describe ".dtach_on_path?" do
    it "returns true when dtach exists somewhere on PATH" do
      Dir.mktmpdir do |bin_dir|
        fake = File.join(bin_dir, "dtach")
        File.write(fake, "#!/bin/sh\n")
        FileUtils.chmod(0o755, fake)
        with_path(bin_dir) do
          expect(described_class.dtach_on_path?).to be true
        end
      end
    end

    it "returns false when dtach is not on PATH" do
      with_path("/nonexistent/sandbox/#{SecureRandom.hex(4)}") do
        expect(described_class.dtach_on_path?).to be false
      end
    end
  end

  describe ".ensure_available!" do
    it "raises DtachUnavailable when dtach is missing" do
      with_path("/nonexistent/sandbox/#{SecureRandom.hex(4)}") do
        expect { described_class.ensure_available! }
          .to raise_error(described_class::DtachUnavailable)
      end
    end
  end

  describe "#spawn" do
    it "raises when dtach is not on PATH" do
      with_path("/nonexistent/sandbox/#{SecureRandom.hex(4)}") do
        expect { wrapper.spawn(["true"]) }.to raise_error(described_class::DtachUnavailable)
      end
    end

    it "rejects an empty command" do
      allow(described_class).to receive(:ensure_available!)
      expect { wrapper.spawn([]) }.to raise_error(ArgumentError, /command/)
    end

    it "clears any stale pid file before spawning", skip: ("needs dtach installed" unless described_class.dtach_on_path?) do
      File.write(wrapper.pid_path, "999999")
      allow(described_class).to receive(:ensure_available!)
      # Stubbed spawn so we don't actually exec dtach:
      allow(Process).to receive(:spawn).and_raise(Errno::ENOENT)
      expect { wrapper.spawn(["true"]) }.to raise_error(Errno::ENOENT)
      # stale pid file should have been cleared
      expect(File.exist?(wrapper.pid_path)).to be false
    end
  end

  describe "#stop when the child survives SIGKILL" do
    it "returns :still_alive when alive? remains true after SIGKILL + SIGKILL_REAP_WAIT" do
      File.write(wrapper.pid_path, Process.pid.to_s)

      original_kill = Process.method(:kill)
      allow(Process).to receive(:kill) do |sig, pid|
        if sig == "TERM" || sig == "KILL"
          1
        else
          original_kill.call(sig, pid)
        end
      end

      expect(wrapper.stop(grace: 0.05)).to eq(:still_alive)
    end
  end

  # End-to-end: actually spawns dtach, confirms pid tracking and stop
  # flow. Skipped automatically when the binary is not installed.
  describe "integration (requires dtach installed)", if: described_class.dtach_on_path? do
    it "spawns a long-running child and tracks its pid, then stops it cleanly" do
      child = wrapper.spawn(["sleep", "30"])
      expect(child).to be_a(Integer)
      expect(wrapper.alive?).to be true

      result = wrapper.stop(grace: 2)
      expect(%i[stopped forced already_gone]).to include(result)
      expect(wrapper.alive?).to be false
      wrapper.cleanup
    end

    it "returns :already_gone when the child already exited" do
      wrapper.spawn(["true"])
      sleep(0.2)
      expect(wrapper.stop(grace: 1)).to eq(:already_gone)
      wrapper.cleanup
    end
  end

  def with_path(new_path)
    previous = ENV["PATH"]
    ENV["PATH"] = new_path
    yield
  ensure
    ENV["PATH"] = previous
    described_class.reset_availability_cache!
  end
end
