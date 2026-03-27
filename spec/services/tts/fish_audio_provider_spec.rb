require "rails_helper"

RSpec.describe Tts::FishAudioProvider do
  let(:provider) do
    described_class.new(
      name: "fish_audio",
      base_url: "https://api.fish.audio",
      api_key: "fa-secret-key"
    )
  end

  describe "#synthesize" do
    let(:audio_bytes) { "\xFF\xFB\x90\x00".b }

    it "posts to the correct endpoint with correct headers and body" do
      expect(provider).to receive(:post_binary).with(
        "https://api.fish.audio/v1/tts",
        headers: {
          "Authorization" => "Bearer fa-secret-key"
        },
        body: {
          text: "Ola mundo",
          reference_id: "ref-voice-123",
          format: "mp3"
        }
      ).and_return(audio_bytes)

      result = provider.synthesize(
        text: "Ola mundo",
        voice: "ref-voice-123",
        language: "pt-BR",
        model: nil,
        format: "mp3",
        settings: {}
      )

      expect(result).to be_a(Tts::Result)
      expect(result.audio_data).to eq(audio_bytes)
      expect(result.content_type).to eq("audio/mpeg")
    end

    it "maps wav format to audio/wav content_type" do
      expect(provider).to receive(:post_binary).and_return(audio_bytes)

      result = provider.synthesize(
        text: "Test", voice: "v1", language: "en",
        model: nil, format: "wav", settings: {}
      )

      expect(result.content_type).to eq("audio/wav")
    end
  end
end
