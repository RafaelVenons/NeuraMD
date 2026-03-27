module Tts
  class ElevenlabsProvider < BaseProvider
    DEFAULT_MODEL = "eleven_multilingual_v2"
    DEFAULT_VOICE_SETTINGS = {stability: 0.5, similarity_boost: 0.75, style: 0.0}.freeze

    def synthesize(text:, voice:, language:, model:, format:, settings:)
      url = "#{base_url}/v1/text-to-speech/#{voice}"
      headers = {
        "xi-api-key" => api_key,
        "Accept" => "audio/mpeg"
      }
      body = {
        text: text,
        model_id: model.presence || DEFAULT_MODEL,
        voice_settings: build_voice_settings(settings)
      }

      audio_data = post_binary(url, headers: headers, body: body)
      Result.new(audio_data: audio_data, content_type: "audio/mpeg")
    end

    private

    def build_voice_settings(settings)
      return DEFAULT_VOICE_SETTINGS.dup if settings.blank?

      {
        stability: settings[:stability] || settings["stability"] || DEFAULT_VOICE_SETTINGS[:stability],
        similarity_boost: settings[:similarity_boost] || settings["similarity_boost"] || DEFAULT_VOICE_SETTINGS[:similarity_boost],
        style: settings[:style] || settings["style"] || DEFAULT_VOICE_SETTINGS[:style]
      }
    end
  end
end
