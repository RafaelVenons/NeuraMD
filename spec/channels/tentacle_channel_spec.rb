require "rails_helper"

RSpec.describe TentacleChannel, type: :channel do
  let(:user) { create(:user) }
  let(:tentacle_id) { SecureRandom.uuid }

  before { stub_connection(current_user: user) }

  it "rejects a subscription without a tentacle_id" do
    subscribe
    expect(subscription).to be_rejected
  end

  it "streams for the requested tentacle_id" do
    subscribe(tentacle_id: tentacle_id)

    expect(subscription).to be_confirmed
    expect(subscription.streams).to include(described_class.broadcasting_for(tentacle_id))
  end

  it "forwards input to TentacleRuntime" do
    subscribe(tentacle_id: tentacle_id)

    expect(TentacleRuntime).to receive(:write)
      .with(tentacle_id: tentacle_id, data: "ls\n")

    perform(:input, "data" => "ls\n")
  end

  it "ignores empty input" do
    subscribe(tentacle_id: tentacle_id)

    expect(TentacleRuntime).not_to receive(:write)

    perform(:input, "data" => "")
  end

  it "forwards resize commands" do
    subscribe(tentacle_id: tentacle_id)

    expect(TentacleRuntime).to receive(:resize)
      .with(tentacle_id: tentacle_id, cols: 120, rows: 40)

    perform(:resize, "cols" => 120, "rows" => 40)
  end

  describe ".broadcast_output" do
    it "publishes an output payload on the tentacle stream" do
      stream = described_class.broadcasting_for(tentacle_id)
      expect(ActionCable.server).to receive(:broadcast)
        .with(stream, hash_including(type: "output", data: "hi"))

      described_class.broadcast_output(tentacle_id: tentacle_id, data: "hi")
    end
  end

  describe ".broadcast_exit" do
    it "publishes an exit payload" do
      stream = described_class.broadcasting_for(tentacle_id)
      expect(ActionCable.server).to receive(:broadcast)
        .with(stream, hash_including(type: "exit", status: 0))

      described_class.broadcast_exit(tentacle_id: tentacle_id, status: 0)
    end
  end
end
