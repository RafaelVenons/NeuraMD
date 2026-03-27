require "rails_helper"

RSpec.describe Tts::GeminiProvider do
  let(:provider) do
    described_class.new(
      name: "gemini",
      base_url: "https://generativelanguage.googleapis.com",
      api_key: "gemini-key"
    )
  end

  describe "#synthesize" do
    let(:audio_b64) { Base64.strict_encode64("\xFF\xFB\x90\x00".b) }
    let(:gemini_response) do
      {
        "candidates" => [{
          "content" => {
            "parts" => [{
              "inlineData" => {
                "mimeType" => "audio/L16;rate=24000",
                "data" => audio_b64
              }
            }]
          }
        }]
      }
    end

    it "posts to the Gemini generateContent endpoint" do
      expect(provider).to receive(:post_json).with(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent",
        headers: {
          "x-goog-api-key" => "gemini-key"
        },
        body: hash_including(
          contents: [{
            parts: [{text: "Hello world"}]
          }],
          generationConfig: hash_including(
            responseModalities: ["AUDIO"],
            speechConfig: hash_including(
              voiceConfig: {
                prebuiltVoiceConfig: {voiceName: "Kore"}
              }
            )
          )
        )
      ).and_return(gemini_response)

      result = provider.synthesize(
        text: "Hello world",
        voice: "Kore",
        language: "en-US",
        model: "gemini-2.5-flash-preview-tts",
        format: "wav",
        settings: {}
      )

      expect(result).to be_a(Tts::Result)
      expect(result.audio_data).to eq("\xFF\xFB\x90\x00".b)
      expect(result.content_type).to eq("audio/wav")
    end

    it "uses default model when nil" do
      expect(provider).to receive(:post_json).with(
        include("gemini-2.5-flash-preview-tts:generateContent"),
        anything
      ).and_return(gemini_response)

      provider.synthesize(
        text: "Test", voice: "Kore", language: "en",
        model: nil, format: "wav", settings: {}
      )
    end

    it "raises RequestError when response has no audio data" do
      bad_response = {"candidates" => [{"content" => {"parts" => [{"text" => "no audio"}]}}]}
      allow(provider).to receive(:post_json).and_return(bad_response)

      expect {
        provider.synthesize(text: "Test", voice: "Kore", language: "en", model: nil, format: "wav", settings: {})
      }.to raise_error(Tts::RequestError, /audio data/)
    end
  end
end
