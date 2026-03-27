require "rails_helper"

RSpec.describe Tts::ProviderRegistry do
  around do |example|
    original_env = ENV.to_h.slice(
      "TTS_ENABLED", "TTS_ELEVENLABS_API_KEY", "TTS_ELEVENLABS_BASE_URL",
      "TTS_FISH_AUDIO_API_KEY", "TTS_FISH_AUDIO_BASE_URL",
      "TTS_GEMINI_API_KEY", "TTS_GEMINI_BASE_URL", "TTS_GEMINI_MODEL",
      "TTS_KOKORO_BASE_URL"
    )
    example.run
  ensure
    ENV.update(original_env)
    # Clear any keys that weren't in original
    %w[TTS_ENABLED TTS_ELEVENLABS_API_KEY TTS_ELEVENLABS_BASE_URL
       TTS_FISH_AUDIO_API_KEY TTS_FISH_AUDIO_BASE_URL
       TTS_GEMINI_API_KEY TTS_GEMINI_BASE_URL TTS_GEMINI_MODEL
       TTS_KOKORO_BASE_URL].each do |key|
      ENV.delete(key) unless original_env.key?(key)
    end
  end

  def clear_tts_env!
    %w[TTS_ENABLED TTS_ELEVENLABS_API_KEY TTS_ELEVENLABS_BASE_URL
       TTS_FISH_AUDIO_API_KEY TTS_FISH_AUDIO_BASE_URL
       TTS_GEMINI_API_KEY TTS_GEMINI_BASE_URL TTS_GEMINI_MODEL
       TTS_KOKORO_BASE_URL].each { |k| ENV.delete(k) }
  end

  describe ".enabled?" do
    it "returns false when TTS_ENABLED is false" do
      clear_tts_env!
      ENV["TTS_ENABLED"] = "false"
      expect(described_class.enabled?).to be false
    end

    it "returns false when no providers configured" do
      clear_tts_env!
      expect(described_class.enabled?).to be false
    end

    it "returns true when a provider is configured" do
      clear_tts_env!
      ENV["TTS_KOKORO_BASE_URL"] = "http://AIrch:8880"
      expect(described_class.enabled?).to be true
    end
  end

  describe ".available_provider_names" do
    before { clear_tts_env! }

    it "includes kokoro when base_url is set" do
      ENV["TTS_KOKORO_BASE_URL"] = "http://AIrch:8880"
      expect(described_class.available_provider_names).to include("kokoro")
    end

    it "includes elevenlabs when api_key is set" do
      ENV["TTS_ELEVENLABS_API_KEY"] = "key"
      expect(described_class.available_provider_names).to include("elevenlabs")
    end

    it "includes gemini when api_key is set" do
      ENV["TTS_GEMINI_API_KEY"] = "key"
      expect(described_class.available_provider_names).to include("gemini")
    end

    it "includes fish_audio when api_key is set" do
      ENV["TTS_FISH_AUDIO_API_KEY"] = "key"
      expect(described_class.available_provider_names).to include("fish_audio")
    end

    it "returns empty when nothing configured" do
      expect(described_class.available_provider_names).to be_empty
    end
  end

  describe ".build" do
    before { clear_tts_env! }

    it "returns ElevenlabsProvider" do
      ENV["TTS_ELEVENLABS_API_KEY"] = "key"
      provider = described_class.build("elevenlabs")
      expect(provider).to be_a(Tts::ElevenlabsProvider)
      expect(provider.api_key).to eq("key")
    end

    it "returns FishAudioProvider" do
      ENV["TTS_FISH_AUDIO_API_KEY"] = "key"
      provider = described_class.build("fish_audio")
      expect(provider).to be_a(Tts::FishAudioProvider)
    end

    it "returns GeminiProvider" do
      ENV["TTS_GEMINI_API_KEY"] = "key"
      provider = described_class.build("gemini")
      expect(provider).to be_a(Tts::GeminiProvider)
    end

    it "returns KokoroProvider" do
      ENV["TTS_KOKORO_BASE_URL"] = "http://AIrch:8880"
      provider = described_class.build("kokoro")
      expect(provider).to be_a(Tts::KokoroProvider)
      expect(provider.base_url).to eq("http://AIrch:8880")
    end

    it "raises ProviderUnavailableError for unconfigured provider" do
      expect { described_class.build("elevenlabs") }
        .to raise_error(Tts::ProviderUnavailableError)
    end

    it "raises ProviderUnavailableError for unknown provider" do
      expect { described_class.build("unknown") }
        .to raise_error(Tts::ProviderUnavailableError)
    end
  end

  describe ".status" do
    before { clear_tts_env! }

    it "returns enabled status and available providers" do
      ENV["TTS_KOKORO_BASE_URL"] = "http://AIrch:8880"
      ENV["TTS_ELEVENLABS_API_KEY"] = "key"

      status = described_class.status
      expect(status[:enabled]).to be true
      expect(status[:available_providers]).to contain_exactly("elevenlabs", "kokoro")
    end
  end

  describe ".voices_for" do
    it "returns voices for kokoro with language" do
      voices = described_class.voices_for("kokoro", language: "pt-BR")
      expect(voices).to be_an(Array)
      expect(voices).not_to be_empty
    end

    it "returns voices for elevenlabs" do
      voices = described_class.voices_for("elevenlabs", language: "en-US")
      expect(voices).to be_an(Array)
      expect(voices).not_to be_empty
    end

    it "returns empty array for unknown provider" do
      voices = described_class.voices_for("unknown", language: "en")
      expect(voices).to eq([])
    end
  end
end
