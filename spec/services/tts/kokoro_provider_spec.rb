require "rails_helper"

RSpec.describe Tts::KokoroProvider do
  let(:provider) do
    described_class.new(
      name: "kokoro",
      base_url: "http://AIrch:8880"
    )
  end

  describe "#synthesize" do
    let(:audio_bytes) { "\xFF\xFB\x90\x00".b }

    it "posts to OpenAI-compatible endpoint" do
      expect(provider).to receive(:post_binary).with(
        "http://AIrch:8880/v1/audio/speech",
        headers: {},
        body: {
          input: "Hello world",
          voice: "af_heart",
          response_format: "mp3",
          speed: 1.0
        }
      ).and_return(audio_bytes)

      result = provider.synthesize(
        text: "Hello world",
        voice: "af_heart",
        language: "en-US",
        model: nil,
        format: "mp3",
        settings: {}
      )

      expect(result).to be_a(Tts::Result)
      expect(result.audio_data).to eq(audio_bytes)
      expect(result.content_type).to eq("audio/mpeg")
    end

    it "passes custom speed from settings" do
      expect(provider).to receive(:post_binary).with(
        anything,
        headers: {},
        body: hash_including(speed: 1.5)
      ).and_return(audio_bytes)

      provider.synthesize(
        text: "Test", voice: "pf_dora", language: "pt-BR",
        model: nil, format: "mp3", settings: {"speed" => 1.5}
      )
    end

    it "does not send authorization header" do
      expect(provider).to receive(:post_binary).with(
        anything,
        headers: {},
        body: anything
      ).and_return(audio_bytes)

      provider.synthesize(
        text: "Test", voice: "v", language: "en",
        model: nil, format: "wav", settings: {}
      )
    end
  end
end
