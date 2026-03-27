module Tts
  class KokoroProvider < BaseProvider
    CONTENT_TYPES = {
      "mp3" => "audio/mpeg",
      "wav" => "audio/wav",
      "opus" => "audio/opus"
    }.freeze

    def synthesize(text:, voice:, language:, model:, format:, settings:)
      url = "#{base_url}/v1/audio/speech"
      headers = {}
      body = {
        input: text,
        voice: voice,
        response_format: format,
        speed: (settings["speed"] || settings[:speed] || 1.0).to_f
      }

      audio_data = post_binary(url, headers: headers, body: body)
      Result.new(audio_data: audio_data, content_type: CONTENT_TYPES.fetch(format, "audio/mpeg"))
    end
  end
end
