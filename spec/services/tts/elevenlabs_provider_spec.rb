require "rails_helper"

RSpec.describe Tts::ElevenlabsProvider do
  let(:provider) do
    described_class.new(
      name: "elevenlabs",
      base_url: "https://api.elevenlabs.io",
      api_key: "el-secret-key"
    )
  end

  describe "#synthesize" do
    let(:audio_bytes) { "\xFF\xFB\x90\x00".b }

    it "posts to the correct endpoint with correct headers and body" do
      expect(provider).to receive(:post_binary).with(
        "https://api.elevenlabs.io/v1/text-to-speech/voice-id-123",
        headers: {
          "xi-api-key" => "el-secret-key",
          "Accept" => "audio/mpeg"
        },
        body: {
          text: "Hello world",
          model_id: "eleven_multilingual_v2",
          voice_settings: {stability: 0.5, similarity_boost: 0.75, style: 0.0}
        }
      ).and_return(audio_bytes)

      result = provider.synthesize(
        text: "Hello world",
        voice: "voice-id-123",
        language: "en-US",
        model: "eleven_multilingual_v2",
        format: "mp3",
        settings: {stability: 0.5, similarity_boost: 0.75, style: 0.0}
      )

      expect(result).to be_a(Tts::Result)
      expect(result.audio_data).to eq(audio_bytes)
      expect(result.content_type).to eq("audio/mpeg")
    end

    it "uses default model when nil" do
      expect(provider).to receive(:post_binary).with(
        anything,
        headers: anything,
        body: hash_including(model_id: "eleven_multilingual_v2")
      ).and_return(audio_bytes)

      provider.synthesize(
        text: "Test", voice: "v1", language: "pt-BR",
        model: nil, format: "mp3", settings: {}
      )
    end

    it "uses default voice settings when settings is empty" do
      expect(provider).to receive(:post_binary).with(
        anything,
        headers: anything,
        body: hash_including(voice_settings: {stability: 0.5, similarity_boost: 0.75, style: 0.0})
      ).and_return(audio_bytes)

      provider.synthesize(
        text: "Test", voice: "v1", language: "en",
        model: nil, format: "mp3", settings: {}
      )
    end
  end
end
