require "rails_helper"

RSpec.describe Tts::GenerateJob, type: :job do
  let(:note) { create(:note) }
  let(:revision) { create(:note_revision, note: note) }
  let(:tts_asset) { create(:note_tts_asset, note_revision: revision) }
  let(:ai_request) do
    create(:ai_request,
      note_revision: revision,
      capability: "tts",
      provider: "kokoro",
      status: "queued",
      input_text: "Hello world",
      metadata: {
        "tts_asset_id" => tts_asset.id,
        "language" => "en-US",
        "voice" => "af_heart",
        "format" => "mp3",
        "settings" => {}
      })
  end

  let(:audio_bytes) { "\xFF\xFB\x90\x04test audio data".b }
  let(:tts_result) { Tts::Result.new(audio_data: audio_bytes, content_type: "audio/mpeg", duration_ms: 5000) }
  let(:provider) { instance_double(Tts::KokoroProvider) }

  before do
    allow(Tts::ProviderRegistry).to receive(:build).with("kokoro").and_return(provider)
    allow(Mfa::AlignService).to receive(:call)
  end

  describe "#perform" do
    it "synthesizes audio and attaches to tts_asset" do
      allow(provider).to receive(:synthesize).and_return(tts_result)

      described_class.perform_now(ai_request.id)

      tts_asset.reload
      expect(tts_asset.audio).to be_attached
      expect(tts_asset.duration_ms).to eq(5000)
      expect(tts_asset.ready?).to be true

      ai_request.reload
      expect(ai_request.status).to eq("succeeded")
      expect(ai_request.completed_at).to be_present
    end

    it "passes correct params to provider.synthesize" do
      expect(provider).to receive(:synthesize).with(
        text: "Hello world",
        voice: "af_heart",
        language: "en-US",
        model: nil,
        format: "mp3",
        settings: {}
      ).and_return(tts_result)

      described_class.perform_now(ai_request.id)
    end

    it "skips canceled requests" do
      ai_request.update!(status: "canceled")
      expect(provider).not_to receive(:synthesize)
      described_class.perform_now(ai_request.id)
    end

    it "marks request as failed on permanent error" do
      allow(provider).to receive(:synthesize)
        .and_raise(Tts::RequestError, "bad voice")

      described_class.perform_now(ai_request.id)

      ai_request.reload
      expect(ai_request.status).to eq("failed")
      expect(ai_request.error_message).to eq("bad voice")
    end

    it "retries on transient error when attempts remain" do
      ai_request.update!(attempts_count: 0, max_attempts: 3)
      allow(provider).to receive(:synthesize)
        .and_raise(Tts::TransientRequestError, "timeout")

      expect(described_class).to receive(:set).with(wait: anything).and_return(described_class)
      expect(described_class).to receive(:perform_later).with(ai_request.id)

      described_class.perform_now(ai_request.id)

      ai_request.reload
      expect(ai_request.status).to eq("retrying")
    end

    it "runs MFA alignment synchronously after audio attach" do
      allow(provider).to receive(:synthesize).and_return(tts_result)

      described_class.perform_now(ai_request.id)

      expect(Mfa::AlignService).to have_received(:call).with(tts_asset)
      expect(tts_asset.reload.alignment_status).to eq("pending").or eq("succeeded")
    end

    it "succeeds even if MFA alignment fails" do
      allow(provider).to receive(:synthesize).and_return(tts_result)
      allow(Mfa::AlignService).to receive(:call).and_raise(Mfa::ExecutionError, "MFA crashed")

      described_class.perform_now(ai_request.id)

      expect(ai_request.reload.status).to eq("succeeded")
      expect(tts_asset.reload.alignment_status).to eq("failed")
    end

    it "fails when max attempts exceeded on transient error" do
      ai_request.update!(attempts_count: 2, max_attempts: 3)
      allow(provider).to receive(:synthesize)
        .and_raise(Tts::TransientRequestError, "timeout")

      described_class.perform_now(ai_request.id)

      ai_request.reload
      expect(ai_request.status).to eq("failed")
    end
  end
end
