require "rails_helper"

RSpec.describe TentacleRuntime, "context-warning" do
  let(:tentacle_id) { SecureRandom.uuid }

  before do
    allow(TentacleChannel).to receive(:broadcast_output)
    allow(TentacleChannel).to receive(:broadcast_exit)
    allow(TentacleChannel).to receive(:broadcast_context_warning)
  end

  after { described_class.reset! }

  def bytes_for(ratio, window: TentacleRuntime::Session::DEFAULT_CONTEXT_WINDOW_TOKENS)
    (window * TentacleRuntime::Session::TOKEN_BYTES_RATIO * ratio).to_i
  end

  it "does not fire below the configured ratio" do
    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

    session.append_to_transcript("x" * bytes_for(0.5))

    expect(TentacleChannel).not_to have_received(:broadcast_context_warning)
  end

  it "fires once when the estimated token ratio crosses the threshold" do
    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

    session.append_to_transcript("x" * bytes_for(0.75))

    expect(TentacleChannel).to have_received(:broadcast_context_warning).with(
      hash_including(tentacle_id: tentacle_id)
    ).once
  end

  it "never writes to the child PTY when the warning fires" do
    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])
    allow(session).to receive(:write).and_call_original

    session.append_to_transcript("x" * bytes_for(0.80))

    expect(session).not_to have_received(:write)
  end

  it "does not fire a second time even after more transcript is appended" do
    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

    session.append_to_transcript("x" * bytes_for(0.75))
    session.append_to_transcript("x" * bytes_for(0.20))

    expect(TentacleChannel).to have_received(:broadcast_context_warning).once
  end

  it "honors a custom context_warning_ratio passed at start" do
    session = described_class.start(
      tentacle_id: tentacle_id,
      command: ["sleep", "5"],
      context_warning_ratio: 0.25
    )

    session.append_to_transcript("x" * bytes_for(0.30))

    expect(TentacleChannel).to have_received(:broadcast_context_warning).once
  end

  it "honors a custom context_window_tokens passed at start" do
    small_window = 1_000
    session = described_class.start(
      tentacle_id: tentacle_id,
      command: ["sleep", "5"],
      context_window_tokens: small_window
    )

    session.append_to_transcript("x" * bytes_for(0.75, window: small_window))

    expect(TentacleChannel).to have_received(:broadcast_context_warning).once
  end

  it "broadcasts a payload with ratio and estimated_tokens" do
    captured = nil
    allow(TentacleChannel).to receive(:broadcast_context_warning) { |**payload| captured = payload }

    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])
    session.append_to_transcript("x" * bytes_for(0.80))

    expect(captured[:tentacle_id]).to eq(tentacle_id)
    expect(captured[:ratio]).to be_within(0.05).of(0.80)
    expect(captured[:estimated_tokens]).to be_a(Integer)
    expect(captured[:estimated_tokens]).to be > 0
  end

  it "counts transcript bytes that were dropped when the live buffer was capped" do
    session = described_class.start(tentacle_id: tentacle_id, command: ["sleep", "5"])

    cap = TentacleRuntime::Session::LIVE_TRANSCRIPT_CAP
    session.append_to_transcript("y" * cap)
    session.append_to_transcript("z" * bytes_for(0.75))

    expect(TentacleChannel).to have_received(:broadcast_context_warning).once
  end
end

RSpec.describe TentacleChannel, ".broadcast_context_warning" do
  it "broadcasts a context-warning message to the tentacle stream" do
    tentacle_id = SecureRandom.uuid
    expect(described_class).to receive(:broadcast_to).with(
      tentacle_id,
      hash_including(type: "context-warning", ratio: 0.75, estimated_tokens: 150_000)
    )

    described_class.broadcast_context_warning(
      tentacle_id: tentacle_id,
      ratio: 0.75,
      estimated_tokens: 150_000
    )
  end
end
