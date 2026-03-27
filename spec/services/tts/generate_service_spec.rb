require "rails_helper"

RSpec.describe Tts::GenerateService do
  let(:user) { create(:user) }
  let(:note) { create(:note) }
  let!(:revision) { create(:note_revision, note: note) }

  let(:params) do
    {
      note: note,
      note_revision: revision,
      text: "Hello world",
      language: "en-US",
      voice: "af_heart",
      provider_name: "kokoro",
      model: nil,
      format: "mp3",
      settings: {}
    }
  end

  before do
    allow(Tts::ProviderRegistry).to receive(:available_provider_names).and_return(%w[kokoro])
  end

  describe ".call" do
    it "creates a NoteTtsAsset and AiRequest on cache miss" do
      allow(Tts::GenerateJob).to receive(:perform_later)

      expect {
        result = described_class.call(**params)
        expect(result[:cached]).to be false
        expect(result[:tts_asset]).to be_a(NoteTtsAsset)
        expect(result[:tts_asset]).to be_persisted
        expect(result[:tts_asset].pending?).to be true
        expect(result[:ai_request]).to be_a(AiRequest)
        expect(result[:ai_request].capability).to eq("tts")
        expect(result[:ai_request].provider).to eq("kokoro")
        expect(result[:ai_request].status).to eq("queued")
      }.to change(NoteTtsAsset, :count).by(1)
        .and change(AiRequest, :count).by(1)
    end

    it "enqueues a GenerateJob" do
      expect(Tts::GenerateJob).to receive(:perform_later).with(kind_of(String))
      described_class.call(**params)
    end

    it "returns cached asset on cache hit" do
      sha = Digest::SHA256.hexdigest("Hello world")
      settings_sha = Digest::SHA256.hexdigest({}.sort.to_json)
      cached = create(:note_tts_asset, :with_audio,
        note_revision: revision,
        text_sha256: sha, language: "en-US", voice: "af_heart",
        provider: "kokoro", model: nil, settings_hash: settings_sha)

      result = described_class.call(**params)
      expect(result[:cached]).to be true
      expect(result[:tts_asset]).to eq(cached)
      expect(result[:ai_request]).to be_nil
    end

    it "computes text_sha256 correctly" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params)
      expected_sha = Digest::SHA256.hexdigest("Hello world")
      expect(result[:tts_asset].text_sha256).to eq(expected_sha)
    end

    it "computes settings_hash correctly" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params.merge(settings: {"speed" => 1.5}))
      expected_hash = Digest::SHA256.hexdigest([["speed", 1.5]].to_json)
      expect(result[:tts_asset].settings_hash).to eq(expected_hash)
    end

    it "stores tts params in AiRequest metadata" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params)
      meta = result[:ai_request].metadata
      expect(meta["tts_asset_id"]).to eq(result[:tts_asset].id)
      expect(meta["language"]).to eq("en-US")
      expect(meta["voice"]).to eq("af_heart")
      expect(meta["format"]).to eq("mp3")
    end

    it "raises error for blank text" do
      expect { described_class.call(**params.merge(text: "")) }
        .to raise_error(Tts::Error, /texto/)
    end

    it "raises error for unavailable provider" do
      allow(Tts::ProviderRegistry).to receive(:available_provider_names).and_return(%w[])
      expect { described_class.call(**params) }
        .to raise_error(Tts::ProviderUnavailableError)
    end

    it "strips wikilinks from text before sending to TTS" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params.merge(text: "Veja [[Nota Teste|f:abc12345-1234-1234-1234-123456789abc]] aqui"))
      expect(result[:ai_request].input_text).to eq("Veja Nota Teste aqui")
    end

    it "strips markdown bold/italic from text" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params.merge(text: "Texto **negrito** e *italico*"))
      expect(result[:ai_request].input_text).to eq("Texto negrito e italico")
    end

    it "strips heading markers from text" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params.merge(text: "# Titulo\nParagrafo"))
      expect(result[:ai_request].input_text).to eq("Titulo Paragrafo")
    end

    it "strips code blocks from text" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      result = described_class.call(**params.merge(text: "Antes ```code aqui``` depois"))
      expect(result[:ai_request].input_text).to eq("Antes depois")
    end

    it "defaults voice to first available when blank" do
      allow(Tts::GenerateJob).to receive(:perform_later)
      allow(Tts::ProviderRegistry).to receive(:voices_for).with("kokoro", language: "en-US").and_return(%w[af_heart bf_emma])
      result = described_class.call(**params.merge(voice: ""))
      expect(result[:tts_asset].voice).to eq("af_heart")
    end
  end
end
