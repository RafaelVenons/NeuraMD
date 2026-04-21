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
end
